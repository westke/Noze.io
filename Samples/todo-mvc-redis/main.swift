// Noze.io Simple Connect + Redis based TodoMVC implementation
// See: http://todomvc.com
// - to compile in Swift 3 invoke: swift build
// - to run result: .build/debug/todo-mvc-redis
// - access backend via:
//     http://todobackend.com/client/index.html?http://localhost:1337/
// - test:
//     http://todobackend.com/specs/index.html?http://localhost:1337/

import http
import console
import connect
import express
import Freddy
import redis

let app = express()

let ourAPI = "http://localhost:1337/"

// MARK: - Middleware

app.use(logger("dev"))
app.use(bodyParser.json())
app.use(cors(allowOrigin: "*"))


// MARK: - Hack Test, bug in spec tool

app.get("/*") { req, _, next in
  // The /specs/index.html sends:
  //   Content-Type: application/json
  //   Accept:       text/plain, */*; q=0.01
  //
  // The tool essentially has the misconception that the API always returns JSON
  // regardless of the Accept header.
  if let ctype = (req.headers[ci: "Content-Type"] as? String) {
    if ctype.hasPrefix("application/json") {
      req.headers[ci: "Accept"] = "application/json"
    }
  }
  next()
}


// MARK: - Storage

// let todos = InMemoryCollectionStore<Todo>()
let todos = RedisCollectionStore<Todo>(redis.createClient())

// MARK: - Routes & Handlers

app.del("/todos/:id") { req, res, _ in
  guard let id = req.params[int: "id"] else { res.sendStatus(400); return }
  todos.delete(id: id) {
    res.sendStatus(200)
  }
}

app.del("/") { req, res, _ in
  todos.deleteAll() {
    res.json([]) // everything deleted, respond with an empty array
  }
}

app.patch("/todos/:id") { req, res, _ in
  guard let id   = req.params[int: "id"] else { res.sendStatus(404); return }
  guard let json = req.body.json         else { res.sendStatus(400); return }
  
  todos.get(id: id) { todo in
    guard var todo = todo else { res.sendStatus(404); return }
    
    if let t = try? json.string("title")   { todo.title     = t }
    if let t = try? json.bool("completed") { todo.completed = t }
    if let t = try? json.int("order")      { todo.order     = t }
    
    todos.update(id: id, value: todo) { todo in // value type!
      res.json(todo)
    }
  }
}

app.put("/todos/:id") { req, res, _ in
  guard let id   = req.params[int: "id"] else { res.sendStatus(404); return }
  guard let json = req.body.json         else { res.sendStatus(400); return }
  
  todos.get(id: id) { todo in
    // a title is required
    guard let t = try? json.string("title") else { res.sendStatus(400); return }
    
    let completed = try? json.bool("completed")
    let order     = try? json.int("order")
    
    if var todo = todo {
      todo.title     = t
      todo.completed = completed ?? false
      todo.order     = order     ?? 0
      
      todos.update(id: id, value: todo) { todo in // value type!
        res.json(todo)
      }
    }
    else { // new record under old id, respect HTTP
      let newTodo = Todo(id: id, title: t,
                         completed: completed ?? false,
                         order:     order     ?? 0)
      
      todos.update(id: id, value: newTodo) { todo in // value type!
        res.status(201).json(todo)
      }
    }
    
  }
}

app.get("/todos/:id") { req, res, _ in
  guard let id = req.params[int: "id"] else { res.sendStatus(404); return }
  
  todos.get(id: id) { todo in
    guard var todo = todo else { res.sendStatus(404); return }
    res.json(todo)
  }
}

app.post("/*") { req, res, _ in
  guard let json = req.body.json else { res.sendStatus(400); return }
  
  guard let t = try? json.string("title") else { res.sendStatus(400); return }
  
  let completed = try? json.bool("completed")
  let order     = try? json.int("order")
  
  todos.nextKey { pkey in
    let newTodo = Todo(id: pkey, title: t,
                       completed: completed ?? false,
                       order:     order     ?? 0)
    
    todos.update(id: pkey, value: newTodo) { todo in // value type!
      res.status(201).json(todo)
    }
  }
}

app.get("/*") { req, res, _ in
  if req.accepts("json") != nil {
    todos.getAll { todos in
      res.json(todos)
    }
  }
  else {
    let clientURL = "http://todobackend.com/client/index.html?\(ourAPI)"
    
    res.send(
      "<html><body><h3>Welcome to the Noze.io Todo MVC Backend</h3>" +
        "<ul>" +
        "<li><a href=\"\(clientURL)\">Client</a></li>" +
        "<ul>" +
      "</body></html>"
    )
  }
}


// MARK: - Run the server

app.listen(1337) {
  print("Server listening: \($0)")
}

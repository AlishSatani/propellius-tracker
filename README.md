## Installation

1. **Install dependencies**

   You can use either Yarn or npm to install the dependencies:

   ```sh
   yarn install
   # or
   npm i
   ```

2. **Set up environment variables**

   Copy the `env.example` file to `.env` and update the variables accordingly. Ensure you have set up Ethereal Mail and your database credentials.

3. **Build the project**

   ```sh
   yarn build
   ```

4. **Install worker**

   ```sh
   yarn worker:install
   ```

5. **Create or reset the database**

   ```sh
   yarn setup:db
   ```

## Running the Application

1. **Run the server**

   ```sh
   yarn dev
   ```

2. **Run the worker**

   ```sh
   yarn worker:start
   ```

## Access

- **GraphQL Playground:** Available at `/graphiql`
- **APIs:** Served at `/graphql`

## Example GraphQL Queries and Mutations

### User Registration

```graphql
mutation Register {
  register(
    input: { email: "user@1.com", password: "Test@123", username: "user1" }
  ) {
    token
  }
}
```

### User Login

```graphql
mutation Login {
  login(input: { username: "user1", password: "Test@123" }) {
    token
  }
}
```

### Get Current User

```graphql
query CurrentUser {
  currentUser {
    id
    username
    email
  }
}
```

### Get Tasks

```graphql
query Tasks {
  tasks(condition: { userId: "26d88cd0-d40b-4e75-9bce-22e32d03272a" }) {
    nodes {
      id
      title
      description
      isCompleted
    }
  }
}
```

### Create Task

```graphql
mutation CreateTask {
  createTask(
    input: {
      task: {
        title: "Task 1"
        description: "This is task description"
        dueDate: "2024-06-16"
      }
    }
  ) {
    task {
      id
      title
      description
      isCompleted
      dueDate
      createdAt
    }
  }
}
```

### Update Task

```graphql
mutation UpdateTask {
  updateTask(
    input: {
      id: "9a9060bf-a777-43c0-9fac-8d5c9ba0afb9"
      patch: {
        title: "Task 2"
        description: "This is task description"
        dueDate: "2024-06-16"
      }
    }
  ) {
    task {
      id
      title
      description
      isCompleted
      dueDate
      createdAt
    }
  }
}
```

### Delete Task

```graphql
mutation DeleteTask {
  deleteTask(input: { id: "f6ce18d5-39c7-47f0-bbca-4e9b84d4bc1c" }) {
    task {
      id
      title
      description
      isCompleted
      dueDate
      createdAt
    }
  }
}
```

### Delete Today's Tasks

```graphql
mutation DeleteTodaysTasks {
  deleteTodayTasks(input: { clientMutationId: "today's tasks" }) {
    success
  }
}
```

### Update Task Status

```graphql
mutation UpdateTaskStatus {
  updateTaskStatus(
    input: { id: "372aa68d-8e45-4f99-bde6-d5eb8bb70d10", isCompleted: true }
  ) {
    task {
      id
      title
      description
      isCompleted
      dueDate
      createdAt
    }
  }
}
```

### Add Reminder

```graphql
mutation AddReminder {
  addReminder(
    input: {
      id: "3c2b7cbf-5ae9-449e-9a3f-454ca9923fe5"
      remindAt: "2024-06-15T15:40:13.810803+05:30"
    }
  ) {
    success
  }
}
```

**Note:** Make sure to add authorization token in headers before using authenticated queries or mutations.
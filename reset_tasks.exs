ClaudeConductor.Repo.query!("UPDATE tasks SET status='pending' WHERE status='running'")
IO.puts("Tasks reset")

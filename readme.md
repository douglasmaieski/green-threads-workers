# Green Threads Workers

This is a small, easy-to-use, green threads library written in assembly for amd64. It requires the IO URING library located at https://github.com/douglasmaieski/io-uring-amd64.

The return codes come from the kernel, so you should use -code to get the correct errno.


## Use cases

- **Input/output-heavy code**. This is the main use case, the library handles input and output, transferring control between threads as their calls are submitted and completed. It uses IO URING under the hood. It first checks if the required operation (reading/writing) is available using epoll, then it does the operation. **In the end, you can write sequential code that executes asynchronously**, similar to JavaScript promises, but implicit.

- **Managing physical threads**. Although this is not the goal of this library, it's possible to use its lock-free message passing code to manage physical threads. You can use `gt_w_send_datum_back` and `gt_wgm_get_datum_back` to pass messages between the main thread and the workers.


## Benefits of using this library

1. Most of the time, there are no syscalls issued, this means the code runs as fast as possible.

2. You can write sequential code that simply works and is automatically asynchronous. It's like bringing JavaScript promises to C.

3. There are no spin locks nor mutexes. The queues are lock-free, single producer, single consumer.


## When not to use this library

- If your code's bottleneck is the processing power, then this won't help at all.

- If you have less than 8 threads, this won't be the most efficient library because it uses 1 thread for the work group manager, 1 thread for the worker manager, and 1 kernel thread spinning to handle the IO URING queue. You need at least 4 threads, but **the benefits show up when you have many threads**.


## Getting started

There are a few concepts to understand how it works and unlock its potential.

**Work group manager:**
- coordinates IO and the worker manager threads
- communicates with the main app thread and passes messages between it and the workers
- has 1 main function that the workers under it run
- can have many worker managers
- should run on its own physical thread

**Worker manager:**
- manages the workers under it
- switches context when IO is being performed
- handles workers
- should run on its own thread

**Worker:**
- runs code from the parent work group manager
- has its own stack
- shares a single thread with other workers under the same worker manager

Sample set up code:
```c
int main(int argc, char *argv[])
{
  // How many worker manager threads
  unsigned long worker_manager_count = 1;
  
  // How many workers per thread
  unsigned long workers_per_manager = 32768;
  
  // Total workers for the work group
  unsigned long total_workers = worker_manager_count * workers_per_manager;

  // This is the work group manager
  struct gt_wgm *wgm;
  
  // Its size depends on how many workers and worker managers it will have
  unsigned long size;
  
  // compute the size for:
  // - up to 16 workers managers
  // - up to 32768 workers per manager
  size = gt_wgm_compute_req_mem(worker_manager_count, total_workers);
  
  // it must be aligned to 16 bytes
  wgm = malloc(size);
  if (!wgm)
    exit(EXIT_FAILURE);
  
  // if this call fails, it doesn't do any cleanup
  // it assumes the program won't be able to continue
  // `work` is the work group procedure
  if(!gt_wgm_init(wgm, worker_manager_count, total_workers, work))
    exit(EXIT_FAILURE);
  
  // allocate and init the workers managers
  struct gt_wm *wms[worker_manager_count];
  for (unsigned long i = 0; i < worker_manager_count; ++i) {
    wms[i] = malloc(sizeof(struct gt_wm));
    if (!wms[i])
      exit(EXIT_FAILURE);
      
    gt_wm_init(wms[i]);
  }
  
  // allocate the workers
  for (unsigned long i = 0; i < worker_manager_count; ++i) {
    struct gt_w *workers = malloc(sizeof(struct gt_w) * workers_per_manager);
    if (!workers)
      exit(EXIT_FAILURE);
    
    for (unsigned long j = 0; j < workers_per_manager; ++j) {
      char *stack = malloc(1024 * 128);
      if (!stack)
        exit(EXIT_FAILURE);
      
      gt_wm_add_worker(wms[i], workers + j,  stack + 1024 * 128);
    }
  }
  
  // register the managers
  for (unsigned long i = 0; i < worker_manager_count; ++i) {
    gt_wgm_add_manager(wgm, wms[i]);
  }
  
  // move every manager to its own thread
  for (unsigned long i = 0; i < worker_manager_count; ++i) {
    thrd_t t;
    int r = thrd_create(&t, dedicated_wm_proc, wms[i]);
    if (r == -1)
      exit(EXIT_FAILURE);
  }
  
  // run the work group manager
  thrd_t t;
  if (thrd_create(&t, dedicated_wgm_proc, wgm) == -1)
    exit(EXIT_FAILURE);
 
  // the rest of the app's code goes here
}
```

Here are the dedicated procedures:

```c
int dedicated_wm_proc(void *arg)
{
  while (1)
    gt_wm_work(arg);
}

int dedicated_wgm_proc(void *arg)
{
  while (1)
    gt_wgm_work(arg);
}

```

Below you can see a simple worker that greets the user:

```c
// The worker function should not return, 
// call gt_w_return(worker) instead
static void work(struct gt_w *worker, union gt_datum datum)
{
  char buf[128];
  long buf_pos = 0;
  long r;
  int fd = datum.i;
  
  // you should check the return code in real production apps
  gt_w_write(worker, fd, -1, "what's your name?\n", 18);
  
  while (1) {
    r = gt_w_read(worker, fd, -1, buf + buf_pos, 128 - buf_pos);
    
    // this is very unlikely to happen, but should always be checked
    if (r == GT_BOTTLENECK)
      continue;
    
    // since the library uses epoll to know when to read,
    // there should usually have data on return
    // return = 0 means the connection was closed
    if (r < 1) {
      gt_w_close(worker, fd);
      
      // you can call gt_w_return() from anywhere
      gt_w_return(worker);
    }
    
    buf_pos += r;
    if (buf[buf_pos - 1] == '\n')
      break;
  }
  
  // also should check below or wrap it into a robust function
  gt_w_write(worker, fd, -1, "HI ", 3);
  gt_w_write(worker, fd, -1, buf, buf_pos - 1);
  gt_w_write(worker, fd, -1, "!\n", 2);
  
  // this should be called
  // returning from the function directly is not supported
  gt_w_return(worker);
}
```

The socket for the worker above should be passed as follows:

```c
while (!gt_wgm_submit_work(wgm, datum)) {
}
```

It's a `while` just in case the input queue is full, which is quite unlikely.

When running the server, you should see something like:
```
ubuntu@ubuntu:~$ nc localhost 8080
what's your name?
Douglas
HI Douglas!
```


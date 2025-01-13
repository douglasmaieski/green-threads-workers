#ifndef GTW_H
#define GTW_H


#define GT_BOTTLENECK -128000L

// work group manager
struct gt_wgm {
  unsigned long opaque[32];
  unsigned long more_data[];
};

// worker manager
struct gt_wm {
  unsigned char opaque[256 + 32768 * 32 + 32768 * 64];
};

// worker
struct gt_w {
  unsigned long opaque[16];
};

// datum for passing work/messages
union gt_datum {
  unsigned long ul;
  long l;
  int i;
  void *ptr;
};

// how much memory to allocate to the work group manager
unsigned long gt_wgm_compute_req_mem(unsigned long max_managers, 
                                     unsigned long max_workers);

// setup a work group manager
long gt_wgm_init(struct gt_wgm *wgm,
                 unsigned long max_managers,
                 unsigned long max_workers,
                 void (*work_cb)(struct gt_w *w, union gt_datum d));

// add worker manager to the work group manager
void gt_wgm_add_manager(struct gt_wgm *wgm, struct gt_wm *manager);

// set up worker manager
void gt_wm_init(struct gt_wm *wm);

// add 1 worker to run under the manager
void gt_wm_add_worker(struct gt_wm *wm, struct gt_w *worker, void *stack);

// send work to a work group
// works is passed to one of the worker managers
long gt_wgm_submit_work(struct gt_wgm *wgm, union gt_datum d);

// get responses back from workers
union gt_datum gt_wgm_get_datum_back(struct gt_wgm *wgm, long *ok);

// main function for the work group manager
// this should run on its own thread non-stop
void gt_wgm_work(struct gt_wgm *wgm);

// main function for the work managers
// this should run on its own thread
void gt_wm_work(struct gt_wm *wm);

// finish running a given work
void gt_w_return(struct gt_w *w);

// return data to the app
union gt_datum gt_w_send_datum_back(struct gt_w *w, union gt_datum datum);

// similar to read()
// you should pass -1 as offset to have the same behavior
long gt_w_read(struct gt_w *w,
               int fd,
               long offset,
               void *buf,
               unsigned long length);

// similar to write()
// you should pass -1 as offset to have the same behavior
long gt_w_write(struct gt_w *w,
                int fd,
                long offset,
                const void *buf,
                unsigned long length);

// similar to close()
long gt_w_close(struct gt_w *w, int fd);

/* TODO:
openat
fsync
socket
connect
accept
send
sendmsg
recv
recvmsg
*/

#endif

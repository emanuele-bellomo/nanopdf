#include "shim.h"
#include <pthread.h>

static pthread_mutex_t nanopdf_mutexes[FZ_LOCK_MAX];
static pthread_once_t nanopdf_mutexes_once = PTHREAD_ONCE_INIT;

static void nanopdf_init_mutexes(void) {
    for (int i = 0; i < FZ_LOCK_MAX; i++){
        pthread_mutex_init(&nanopdf_mutexes[i], NULL);
    }
}

static void nanopdf_lock(void *user, int lock) {
    (void)user;
    pthread_mutex_lock(&nanopdf_mutexes[lock]);
}

static void nanopdf_unlock(void *user, int lock) {
    (void)user;
    pthread_mutex_unlock(&nanopdf_mutexes[lock]);
}

static const fz_locks_context nanopdf_locks = {
    .user = NULL,
    .lock = nanopdf_lock,
    .unlock = nanopdf_unlock,
};

// Public, thread-safe context constructor
fz_context *nanopdf_new_context(void) {
    pthread_once(&nanopdf_mutexes_once, nanopdf_init_mutexes);
    // parameters: (alloc, locks, max_cache (256MB default))
    return fz_new_context(NULL, &nanopdf_locks, FZ_STORE_DEFAULT);
}

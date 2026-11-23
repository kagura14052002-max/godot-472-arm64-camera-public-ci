#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

typedef int (*scandir_fn)(const char *, struct dirent ***,
                          int (*)(const struct dirent *),
                          int (*)(const struct dirent **, const struct dirent **));
int scandir(const char *name, struct dirent ***namelist,
            int (*filter)(const struct dirent *),
            int (*compare)(const struct dirent **, const struct dirent **)) {
    if (strcmp(name, "/dev") == 0) {
        errno = EACCES;
        fputs("GODOT_DENY_DEV_SCANDIR_TEST_INJECTED\n", stderr);
        return -1; // Do NOT touch *namelist: replicates observed glibc failure.
    }
    scandir_fn original = (scandir_fn)dlsym(RTLD_NEXT, "scandir");
    if (!original) { errno = ENOSYS; return -1; }
    return original(name, namelist, filter, compare);
}

typedef int (*scandir64_fn)(const char *, struct dirent64 ***,
                            int (*)(const struct dirent64 *),
                            int (*)(const struct dirent64 **, const struct dirent64 **));
int scandir64(const char *name, struct dirent64 ***namelist,
              int (*filter)(const struct dirent64 *),
              int (*compare)(const struct dirent64 **, const struct dirent64 **)) {
    if (strcmp(name, "/dev") == 0) {
        errno = EACCES;
        fputs("GODOT_DENY_DEV_SCANDIR_TEST_INJECTED\n", stderr);
        return -1;
    }
    scandir64_fn original = (scandir64_fn)dlsym(RTLD_NEXT, "scandir64");
    if (!original) { errno = ENOSYS; return -1; }
    return original(name, namelist, filter, compare);
}

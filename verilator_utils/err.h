// Helper macro
#ifndef ERR_H
#define ERR_H

#include <stdlib.h>
#include <stdio.h>
#define err(fmt, ...) do {                      \
    printf (fmt "\n", ##__VA_ARGS__);           \
    exit (-1);                                  \
  } while (0)

#endif /* ERR_H */

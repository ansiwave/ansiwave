#ifndef _LIBCLIPBOARD_OPTIONS_H_
#define _LIBCLIPBOARD_OPTIONS_H_

#include "libclipboard.h"


struct clipboard_opts* clipboard_init_options()
{
    struct clipboard_opts *options = calloc(1, sizeof(clipboard_opts));
    return options;
}

#endif /* _LIBCLIPBOARD_OPTIONS_H_ */

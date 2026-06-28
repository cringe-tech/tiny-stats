#ifndef CGAMEMODE_H
#define CGAMEMODE_H

// Exposes <notify.h> to Swift: the Darwin notification APIs (notify_register_dispatch,
// notify_get_state, notify_cancel) aren't part of Swift's Darwin overlay, so we surface them
// through this tiny shim module. Used to observe macOS Game Mode.
#include <notify.h>

#endif /* CGAMEMODE_H */

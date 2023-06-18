# oia

use more efficient code for `minetest.get_objects_in_area`.

this is an experimental mod which optionally replaces `minetest.get_objects_in_area` with a more efficient algorithm.
the builtin algorithm checks every object on the server, whereas oia uses a special binary tree to find them more
efficiently. however, it's written in lua instead of c++, so there's definitely more overhead. testing shows
improved performance when there are at least 800 to 1000 active objects, and significantly improved performance
when there are 8000 or more active objects.

caveat!

the positions of objects are only updated once per server step. this means that if a mod creates an object, or moves
it to a different location, oia will not know about that until the next server step, so the list of objects may be
incomplete.

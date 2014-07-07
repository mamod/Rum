Rum is still in very pre alpha :)
=================================

This is an attempt to port node js API and libuv to pure perl

Project Notes
=============

* Currently versioning and code control done on my local machine not through github

* Porting libuv to pure perl - see (Rum::Loop)

* Porting Node core modules

* Only stable and frozen node modules, experimental and unstable modules will be ported once they marked as stable

* Using perl core modules only

TODO NEXT
=========

* Kqueue for bsd instead of select

* http/https modules

* Fix filesystem (fs.pm) module

* IPv6 - currently only IPv4 supported 

Examples
========

See examples folder, you can also look at the tests especially t/Loop
and tests folder

Is it of any use?
=================

What do you think?

For me, I'm really not sure, but it was a very fun and educated experience, I got inside
libuv and node internals using my favorite language :)

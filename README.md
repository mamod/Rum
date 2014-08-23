Rum is still in very pre alpha :)
=================================

[![Build Status](https://travis-ci.org/mamod/Rum.svg?branch=master)](https://travis-ci.org/mamod/Rum)

This is an attempt to port node js API and libuv to pure perl

Project Notes
=============

* Currently versioning and code control done on my local machine not through github

* Porting libuv to pure perl - see (Rum::Loop)

* Porting Node core modules

* Only stable and frozen node modules, experimental and unstable modules will be ported once they marked as stable

* Using perl core modules only

Implemented Modules
===================

* Path

* Net

* http

* module

* Events

* Stream

* Timers

* Child Process

TODO NEXT
=========

* Kqueue for bsd instead of select

* SSL & https

* UDP/Datagram

* Fix filesystem (fs.pm) module

* IPv6 - currently only IPv4 supported

* URL

Examples
========

See examples folder, you can also look at the tests especially ./t/Loop
and ./tests folders

Is it of any use?
=================

What do you think?

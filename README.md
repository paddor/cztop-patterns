# CZTop-BinaryStar

This is currently just a very simple implementation of the [Binary Star](http://zguide.zeromq.org/page:all#Binary-Star-Implementation)
 pattern from the zguide in Ruby using [CZTop](https://github.com/paddor/cztop).

## Usage

Start the primary instance with `./bstarsrv -p` and the backup one with `./bstarsrv -b`. The client can be started using `./bstarcli`.

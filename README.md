# CZTop-Patterns

This will be a collection of reusable patterns from the Zguide, implemented using [CZTop](https://github.com/paddor/cztop).

## Binary Star
Check out CZTop::Patterns::BSar. It's the [Binary
Star](http://zguide.zeromq.org/page:all#Binary-Star-Implementation) pattern in
resuable form. There's an example using it in the
[examples](https://github.com/paddor/cztop-patterns/blob/master/examples)
directory. Start the primary instance with `./bstar_example.rb -p` and the backup one with `./bstar_example.rb -b`. The client can be started using `./bstarcli` from the test/ directory (see below).

You can find a quick and dirty, self-contained version of the Binary Star
pattern in the
[test](https://github.com/paddor/cztop-patterns/blob/master/test) directory.
Start the primary instance with `./bstarsrv -p` and the backup one with
`./bstarsrv -b`. The client can be started using `./bstarcli`.

## Lazy Pirate
tbd

## Clustered Hashmap Protocol (CHP)
tbd

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/paddor/cztop-patterns.

To run the tests before/after you made any changes to the source and have
created a test case for it, use `rake spec`.

## License

The gem is available as open source under the terms of the [ISC License](http://opensource.org/licenses/ISC).
See the [LICENSE](https://github.com/paddor/cztop-patterns/blob/master/LICENSE) file.

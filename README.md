# pbzx stream parser

This repository is a fork of PHPdev32's implementation of the `pbzx` stream
parser program of which the original source code can be found [here][source].
Pbzx is a format employed in later versions of OSX disk images (starting with
10.10) to encode payload data in `.pkg` files. Pbzx unpacks `.pkg` files and
outputs to stdout to be unpacked with `cpio`. Note that `.pkg` files are plain
`.xar` archives.

    pbzx SomePkg.pkg | cpio -i

  [source]: www.tonymacx86.com/general-help/135458-pbzx-stream-parser.html

To compile `pbzx`, do

    clang -llzma -lxar -I /usr/local/include pbzx.c -o pbzx

## Changelog

__v1.0.0__

- Initial version with exact code from [source].

# ViewBuffer - Schemaless Codeless Self-Describing Zero-Copy Flat Buffer for D

Self-describing flat buffer for D. No schemas or code gen required. Viewbuffer is slice-oriented and it's home is D, but will be adapted for read/write between multiple languages. With ZLIB compression / decompression support.

Current read support for:

* D (working)
* C, Java, Swift, Kotlin, Rust, Go (wip)

Current write support for:

* Java (working)
* D, C, Swift, Kotlin, Rust, Go (wip)

Minimal code to easily port read/write to different languages as required.

The binary format is relatively simple:

| # Bytes | Mandatory | Description               | Notes                            |
|---------|-----------|---------------------------|----------------------------------|
| 4       | Y         | Magic "VBUF"              | Value of `0x46554256`            |
| 1       | Y         | ViewBuffer version        | e.g. `1` at the moment           |
| 1       | Y         | Flags                     | See below                        |
| 2       | Y         | User-defined blob version | e.g. `1`                         |
| 4       | Y         | Header size               |                                  |
| 4       | Y         | Compressed blob size      |                                  |
| 4       | Y         | Decompressed blob size    |                                  |
| 16      | N         | Struct encoding hash      | Depends on flag bit 2            |
| 2       | N         | Struct encoding length    | Depends on flag bit 1            |
| 1+      | N         | Struct encoding           | Depends on flag bit 1            |
| ...     |           |                           |                                  |
| 0-3     | N         | Padding                   | To 4-byte alignment              |
| 4       | Y         | Number of offsets `N`     | Offsets to slice pointers        |
| 4N      | N         | List of offsets           | At least 0 offsets, 4 bytes each |
| ...     |           |                           |                                  |
| 1+      | Y         | Data blob                 | Compressed on flag bit 0         |
| ...     |           |                           |                                  |

Offsets are bytes from the start of the blob which need adjusting to update pointers depending on where the blob is loaded into memory on the target machine. This is all automatic.

Currently available flags are:

| Bit | Effect When Set                                          |
|-----|----------------------------------------------------------|
| 0   | Blob compression on                                      |
| 1   | Includes the struct encoding in the ViewBuffer           |
| 2   | Includes a truncated SHA-256 hash of the struct encoding |

# TODO

* Add support for more types, e.g. `double`, etc
* Ensure signed / unsigned compatibility
* Add more tests
* Add further language support (e.g. D writer, Java reader, etc)

# Running
The project contains version controlled IntelliJ run configurations if you want to use the IntelliJ IDE.

Or to run with `dub` command line:
```bash
dub test --config default     # regular
dub test --config betterc     # BetterC compatibility
```
# Troubleshooting
On Mac if running from the command line, if you get this error
```bash
gcc-14: error: unrecognized command-line option '-target'
Error: /opt/homebrew/bin/gcc-14 failed with status: 1
Error ldc2 failed with exit code 1.
```
you'll probably need to run this in the command line:
```bash
export D_COMPILER=ldc2
export CC=clang
export CXX=clang++
```

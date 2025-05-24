module core.stdc.zlib;

extern (C)
{
    /// zlib returns Z_OK (0) on success
    enum Z_OK = 0;

    /**
     * Decompress `srcLen` bytes at `src` into the buffer at `dest`
     * of size `*destLen`.  On entry `*destLen` must be the size
     * of the `dest` buffer; on return it will be set to the
     * actual number of bytes written.
     */
    int uncompress(ubyte* dest,
        size_t* destLen,
        const ubyte* src,
        size_t srcLen) @nogc nothrow;
    // ...add other zlib functions/constants here if needed
}

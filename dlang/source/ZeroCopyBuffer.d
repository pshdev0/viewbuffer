module dzero;

import core.stdc.stdio : FILE, fopen, fread, fclose, fseek, ftell, fclose, printf;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset, strcmp;

enum ENCODE_SEPARATOR = ',';
enum ENCODE_STRUCT = '$';
enum ENCODE_SLICE = '*';
enum ENCODE_INSITU_STRUCT = '^';
enum ENCODE_ARRAY = '[';
enum TAB = "   ";

struct SaferRawSlice(T) {
    T[]    data;
    bool   _valid;
    bool   _secret;
    string id;

    @disable this();                    // no default constructor
    @disable SaferRawSlice opAssign(typeof(this)); // disable default copy-assign

    // move-postblit: steals resources from src
    this(ref SaferRawSlice src) @nogc nothrow {
        // steal fields
        data    = src.data;
        _valid  = src._valid;
        _secret = src._secret;
        id      = src.id;

        // leave src inert
        src.data    = null;
        src._valid  = false;
        src._secret = false;
        src.id      = null;
    }

    this(T[] slice) @nogc nothrow {
        this(slice.ptr, slice.length, false);
    }

    this(T* ptr, size_t length, bool secret = false) @nogc nothrow {
        data    = ptr[0 .. length];
        _valid  = true;
        _secret = secret;
    }

    ~this() @nogc nothrow {
        if (_valid && data.ptr !is null) {
            if (_secret) {
                memset(data.ptr, 0, data.length * T.sizeof);
                printf("Memory sanitised and ");
            }
            free(data.ptr);
            printf("SaferRawSlice buffer freed\n");
        }
    }

    T[] slice() @nogc nothrow {
        return data;
    }

    static SaferRawSlice!T empty() @nogc nothrow {
        return SaferRawSlice!T.init;
    }

    bool valid() @nogc nothrow {
        return _valid;
    }

    // Explicit move helper
    static SaferRawSlice!T move(ref SaferRawSlice!T src) @nogc nothrow {
        auto tmp = src;       // uses move-postblit
        src.data    = null;
        src._valid  = false;
        src._secret = false;
        src.id      = null;
        return tmp;
    }
}

SaferRawSlice!ubyte loadViewBuffer(const char* fileName) {

    /*

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
        | 0-3     | Y         | Padding                   | To 4-byte alignment              |
        | 4       | Y         | Number of offsets `N`     | Offsets to slice pointers        |
        | 4N      | N         | List of offsets           | At least 0 offsets, 4 bytes each |
        | ...     |           |                           |                                  |
        | 1+      | Y         | Data blob                 | Compressed on flag bit 0         |
        | ...     |           |                           |                                  |

     */

    /*
        DECODE THE MAIN HEADER DETAILS
     */

    auto header1 = loadBinary(fileName, 0, 20); // read only first 20 bytes
    auto headerSlice1 = header1.slice();
    auto headerPtr1 = headerSlice1.ptr;

    // magic
    int magic = *cast(int*) &headerPtr1[0];
    if (magic != 0x46554256) {
        printf("Incorrect view buffer format\n");
        printf("magic %d\n", magic);
        return SaferRawSlice!ubyte.empty();
    }
    printf("ViewBuffer file found\n");

    // view buffer version
    int viewBufferVersion = cast(int)headerPtr1[4];
    if (viewBufferVersion != 1) {
        printf("Unknown view buffer version: %i\n", viewBufferVersion);
        return SaferRawSlice!ubyte.empty();
    }

    // flags
    ubyte flags = cast(ubyte)headerPtr1[5];
    bool compressed = flags & 1 ? true : false;
    bool encodingPresent = flags & 2 ? true : false;
    bool encodingVersionHashPresent = flags & 4 ? true : false;

    if(compressed) printf(TAB ~ "Data is compressed\n"); else printf(TAB ~ "Data is not compressed\n");

    // user-defined blob version
    short userDefinedBlobVersion = *cast(short*) &headerPtr1[6];
    printf(TAB ~ "User defined schema version: %d\n", userDefinedBlobVersion);

    // header size
    int headerSize = *cast(int*) &headerPtr1[8];
    printf(TAB ~ "header size = %d\n", headerSize);

    // compressed size (always present, even if not compressed)
    int compressedSize = *cast(int*) &headerPtr1[12];
    printf(TAB ~ "compressed size = %d\n", compressedSize);

    // final blob size
    int finalBlobSize = *cast(int*) &headerPtr1[16];
    printf(TAB ~ "final blob size = %d\n", finalBlobSize);

    /*
        GET THE BLOB BYTES (POSSIBLY COMPRESSED)
     */

    ubyte[] rawSlice;

    if (compressed) {
        // read compressed bytes, then decompress into a GC‑ or malloc‑owned slice
        auto temp    = loadBinary(fileName, headerSize, headerSize + compressedSize);
        rawSlice     = decompress(temp.slice(), finalBlobSize);
    }
    else {
        // read uncompressed bytes
        auto temp    = loadBinary(fileName, headerSize, headerSize + finalBlobSize);
        rawSlice     = temp.slice();
    }

    // 2) Now construct exactly one SaferRawSlice from that slice
    auto decompressedBlob = SaferRawSlice!ubyte(rawSlice);
    auto decompressedBlobSlice = decompressedBlob.slice();

    /*
        DECODE REMAINDER OF THE HEADER AND UPDATE THE POINTER OFFSETS
     */

    auto header2 = loadBinary(fileName, 20, headerSize);
    auto headerSlice2 = header2.slice();
    auto headerPtr2 = headerSlice2.ptr;

    auto dynamicIndex = 0;

    if(encodingVersionHashPresent) {
        printf("Schema version hash: ");
        for(auto c1 = 0; c1 < 16; c1++) printf("%02x", headerPtr2[dynamicIndex++]);
        printf("\n");
    }
    else printf("No schema version hash found\n");

    if(encodingPresent) {
        short structEncodingLength = *cast(short*) &headerPtr2[dynamicIndex];
        dynamicIndex += 2;
        printf("struct encoding length %d\n", structEncodingLength);
        string structEncoding = cast(string)headerPtr2[dynamicIndex .. dynamicIndex + structEncodingLength];
        generateStructs(structEncoding);
        dynamicIndex += structEncodingLength;
    }

    // get number of offsets to update
    int numOffsets = *cast(int*) &headerPtr2[dynamicIndex];
    dynamicIndex += 4;

    size_t base = cast(size_t) decompressedBlobSlice.ptr;

    // determine slice layout
    size_t ptrOffset = getSliceLayout();

    // update all offsets to be pointers
    for (int c1 = 0; c1 < numOffsets; c1++) {
        int offset = *cast(int*) &headerPtr2[dynamicIndex];
        dynamicIndex += 4;

        size_t* p = cast(size_t*)(base + offset);
        size_t ptrVal = p[0];
        size_t lenVal = p[1];

        ptrVal += base;

        if (ptrOffset > 0) {
            p[0] = lenVal;
            p[1] = ptrVal;
        }
        else {
            p[0] = ptrVal;
            p[1] = lenVal;
        }
    }

    // headerSlice1, headerSlice2, and compresedBlobSlice (if the data was compressed)
    // memory will be deallocated on scope exit via SaferRawSlice
    return SaferRawSlice!ubyte.move(decompressedBlob);
}

extern(C) nothrow @nogc int posix_memalign(void** memptr, size_t alignment, size_t size);

SaferRawSlice!ubyte loadBinary(const char* fileName, size_t start = 0, size_t end = 0) @nogc nothrow {
    FILE* file = fopen(fileName, "rb");
    if (file is null) {
        printf("Could not load file\n");
        return SaferRawSlice!ubyte.empty();
    }

    // get file size
    fseek(file, 0, 2);
    long fileSize = ftell(file);
    fseek(file, 0, 0);
    printf("file size %zu\n", fileSize);

    if (end == 0 || end > cast(size_t)fileSize)
    end = cast(size_t)fileSize;

    if (start >= end) {
        printf("Invalid range: start >= end\n");
        fclose(file);
        return SaferRawSlice!ubyte.empty();
    }

    size_t bytesToRead = end - start;

    // allocate buffer
    void* ptr;
    int res = posix_memalign(&ptr, 16, bytesToRead);
    if (res != 0 || ptr is null)
    assert(0, "posix_memalign failed");

    ubyte* buffer = cast(ubyte*) ptr;
    scope(exit) {
        //free(buffer);
        printf("Returning from loadBinary - malloced memory is automatically managed via SaferRawSlice\n");
    }

    if (fseek(file, cast(long)start, 0) != 0) {
        printf("fseek failed\n");
        fclose(file);
        free(buffer);
        return SaferRawSlice!ubyte.empty();
    }

    size_t readSize = fread(buffer, 1, bytesToRead, file);
    fclose(file);
    if (readSize != bytesToRead) {
        free(buffer);
        return SaferRawSlice!ubyte.empty();
    }

    return SaferRawSlice!ubyte(buffer, readSize);
}

T* getViewBufferSliceAs(T)(ubyte[] rawData) @nogc nothrow {
    return cast(T*)(rawData.ptr);
}

int getSliceLayout() @nogc nothrow {
    ubyte* raw = cast(ubyte*) malloc(16);
    if(raw is null) {
        printf("! Could not determine slice ordering, defaulting to ptr-len order");
        return 0; // on fail, defaults to [ptr][len] ordering, which may not be correct on all systems
    }

    raw[0] = 42;
    ubyte[] slice = raw[0 .. 1];
    size_t* slicePtr = cast(size_t*)&slice;

    int layout = slicePtr[0] == 1 ? 8 : 0;

    free(raw);
    return layout;
}

string getType(string code) @nogc nothrow {
    // BetterC compatible:
    if (code == "st")    return "immutable(char)";
    else if (code == "i1") return "ubyte";
    else if (code == "i2") return "short";
    else if (code == "i4") return "int";
    else if (code == "f4") return "float";
    else if (code == "bl") return "bool";
    else if (code == "bp") return "ubyte*";
    else return code;
}

version (BetterC) {
    import core.stdc.stdlib : malloc, free;
    import core.stdc.zlib   : uncompress, Z_OK;
    import core.stdc.stdio  : printf;

    /**
     * Decompress `comp` into a newly malloc’d buffer of size `expectedSize`.
     * Returns a D slice pointing at that buffer; you must call `free(out.ptr)`
     * when you’re done with it.
     */
    ubyte[] decompress(const(ubyte)[] comp, size_t expectedSize) @nogc nothrow
    {
        auto destPtr = cast(ubyte*) malloc(expectedSize);
        if (destPtr is null)
        return [];                        // out of memory → empty slice

        size_t destLen = expectedSize;
        int status = uncompress(destPtr,
        &destLen,
        comp.ptr,
        comp.length);
        if (status != Z_OK)
        {
            free(destPtr);
            return [];
        }

        printf("Decompressed size: %zu\n", destLen);

        // build and return the slice
        return destPtr[0 .. destLen];
    }
}
else {
    import core.stdc.stdlib : malloc, free;
    import core.stdc.zlib   : uncompress, Z_OK;
    import core.stdc.stdio  : printf;

    ubyte[] decompress(const(ubyte)[] comp, size_t expectedSize) {
        auto destPtr = cast(ubyte*) malloc(expectedSize);
        if (destPtr is null) return [];

        size_t destLen = expectedSize;
        int status = uncompress(destPtr, &destLen, comp.ptr, comp.length);
        if (status != Z_OK) {
            free(destPtr);
            return [];
        }

        printf("Decompressed size: %zu\n", destLen);
        return destPtr[0 .. destLen];
    }
}


void generateStructs(string structEncoding) @nogc nothrow {
    size_t start = 0;
    size_t len = structEncoding.length;
    bool structOpen = false;

    printf("Struct encoding: %.*s\n\n", cast(int)structEncoding.length, structEncoding.ptr);

    for (size_t i = 0; i <= len; ++i) {
        if (i == len || structEncoding[i] == ENCODE_SEPARATOR) {
            auto token = structEncoding[start .. i];

            if (token.length == 0) {
                start = i + 1;
                continue;
            }

            // trim
            while (token.length > 0 && (token[$ - 1] == ' ')) {
                token = token[0 .. $ - 1];
            }

            immutable first = token[0];

            // dispatch on first character
            switch(first) {
                case ENCODE_STRUCT:
                    if (structOpen) printf("}\n\n");
                    printf("struct %.*s {\n", cast(int)(token.length - 1), token.ptr + 1);
                    structOpen = true;
                    break;
                case ENCODE_SLICE:
                    // slice field
                    size_t index = 0;
                    for (index = 1; index < token.length; ++index) {
                        if (token[index] == ENCODE_ARRAY)
                        break;
                    }
                    if (index == token.length) {
                        printf("!! Malformed slice token\n");
                        return;
                    }
                    auto name = token[1 .. index];
                    auto type = token[(index + 1) .. $];

                    printf("   %.*s[] %.*s;\n",
                    cast(int)getType(type).length, getType(type).ptr,
                    cast(int)name.length, name.ptr);
                    break;
                case ENCODE_INSITU_STRUCT:
                    // in-situ struct insertion
                    size_t index = 0;
                    for (index = 1; index < token.length; ++index) {
                        if (token[index] == ENCODE_STRUCT)
                        break;
                    }
                    if (index == token.length) {
                        printf("!! Malformed in-situ struct token\n");
                        return;
                    }
                    auto varName = token[1 .. index];
                    auto structName = token[(index + 1) .. $];

                    printf("   %.*s %.*s;\n",
                    cast(int)structName.length, structName.ptr,
                    cast(int)varName.length, varName.ptr);
                    break;
                    default:
                    // scalar field
                    auto type = token[0 .. 2];
                    auto name = token[2 .. $];

                    printf("   %.*s %.*s;\n",
                    cast(int)getType(type).length, getType(type).ptr,
                    cast(int)name.length, name.ptr);
                    break;
            }

            start = i + 1;
        }
    }

    if (structOpen) printf("}\n");
}

unittest {
    struct Device {
        immutable(char)[] id;
        int statusCode;
    }

    struct Network {
        immutable(char)[] id;
        Device[] devices;
    }

    struct Theme {
        float hue;
        float saturation;
        float brightness;
    }

    struct Widget {
        immutable(char)[] id;
        immutable(char)[] type;
        bool enabled;
        float posX;
        float posY;
    }

    struct Dashboard {
        immutable(char)[] id;
        Theme theme;
        Widget[] widgets;
    }

    struct DataBlob {
        int length;
        ubyte[] compressedPayload;
    }

    struct Step {
        int phase;
        int durationMs;
    }

    struct Transform {
        immutable(char)[] id;
        int priority;
        Step[] steps;
    }

    struct Packet {
        immutable(char)[] id;
        int size;
        ubyte[] compressedBytes;
        ubyte[] decompressedBytes;
    }

    struct PipelineConfig {
        immutable(char)[] endpoint;
        Network[] networks;
        Dashboard[] dashboards;
        DataBlob[] dataBlobs;
        Transform[] transforms;
        Packet[] packets;
    }

    auto rawData = loadViewBuffer("../../data/pipeline.bin");
    if(!rawData.valid()) {
        printf("Could not load the buffer\n");
        return;
    }
    auto fb = getViewBufferSliceAs!PipelineConfig(rawData.slice());

    if(fb is null) {
        printf("error viewing buffer");
        return;
    }

    // decompress bytes into dummy slices !
    fb.packets[0].decompressedBytes = decompress(fb.packets[0].compressedBytes, fb.packets[0].size);

    version(BetterC) {
        printf("len0 = %d\n", fb.sounds[0].decompressedBytes.length);
        printf("len1 = %d\n", fb.sounds[1].decompressedBytes.length);
    }
    else {
        import std.stdio;
        writeln(*fb);
    }
}

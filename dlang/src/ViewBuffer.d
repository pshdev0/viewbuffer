module ViewBuffer;

import core.stdc.stdio : FILE, fopen, fread, fseek, ftell, fclose, printf;
import core.stdc.stdlib : malloc, free;
import std.algorithm.mutation : move;

enum ENCODE_SEPARATOR = ',';
enum ENCODE_STRUCT = '$';
enum ENCODE_SLICE = '*';
enum ENCODE_INSITU_STRUCT = '^';
enum ENCODE_ARRAY = '[';
enum TAB = "   ";

struct SaferRawSlice(T) {
    private T[]   _data;
    private string _id;

    // move-only: disable postblit copy & copy-assign
    @disable this(this);
    @disable void opAssign(SaferRawSlice rhs);

    // adopt a malloc’d slice + identifier
    this(T[] slice, string id) @nogc nothrow {
        _data = slice;
        _id   = id;
    }

    // empty factory
    static SaferRawSlice!T empty() @nogc nothrow {
        return SaferRawSlice!T.init;
    }

    // check validity
    @property bool valid() const @nogc nothrow {
        return _data.ptr !is null;
    }

    // RAII cleanup + logging
    ~this() @nogc nothrow {
        if (_data.ptr) {
            printf("SaferRawSlice: freeing buffer [%.*s]...\n", cast(int)_id.length, _id.ptr);
            free(_data.ptr);
            printf("SaferRawSlice: buffer freed  [%.*s]\n", cast(int)_id.length, _id.ptr);
        }
    }

    // slice-style access
    @property size_t length() const @nogc nothrow { return _data.length; }
    @property T* ptr() @nogc nothrow { return _data.ptr;    }
    ref T opIndex(size_t i) @nogc nothrow { return _data[i];      }
    T[] opSlice() @nogc nothrow { return _data;         }
    const(T)[] opSlice() const @nogc nothrow { return _data;         }

    // explicit .slice() convenience
    T[] slice() @nogc nothrow { return _data; }
    const(T)[] slice() const @nogc nothrow { return _data; }

    // expose the id
    @property string id() const @nogc nothrow { return _id; }
}

// helper that returns the right slice in one shot
SaferRawSlice!ubyte loadDecompressedBlob(const char* fileName, bool compressed, size_t headerSize, size_t compressedSize, size_t finalBlobSize) {
    if (compressed) {
        auto temp = loadBinary(fileName, "compressed blob", headerSize, headerSize + compressedSize);
        auto raw = decompress(temp.slice(), finalBlobSize);
        return SaferRawSlice!ubyte(raw, "decompressed blob");
    }
    else {
        return loadBinary(fileName, "original blob", headerSize, headerSize + finalBlobSize);
    }
}

SaferRawSlice!ubyte loadViewBuffer(const char* fileName) {

    /*
        DECODE THE MAIN HEADER DETAILS
     */

    auto header1 = loadBinary(fileName, "header1 blob", 0, 20); // read only first 20 bytes
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

    auto decompressedBlob = loadDecompressedBlob(
        fileName,
        compressed,
        headerSize,
        compressedSize,
        finalBlobSize
    );

    if (!decompressedBlob.valid) return SaferRawSlice!ubyte.empty();
    auto decompressedBlobSlice = decompressedBlob.slice();

    /*
        DECODE REMAINDER OF THE HEADER AND UPDATE THE POINTER OFFSETS
     */

    auto header2 = loadBinary(fileName, "header2 blob", 20, headerSize);
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
    return move(decompressedBlob);
}

extern(C) nothrow @nogc int posix_memalign(void** memptr, size_t alignment, size_t size);

SaferRawSlice!ubyte loadBinary(const char* fileName, string id, size_t start = 0, size_t end = 0) @nogc nothrow {
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

    return SaferRawSlice!ubyte(buffer[0.. readSize], id);
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
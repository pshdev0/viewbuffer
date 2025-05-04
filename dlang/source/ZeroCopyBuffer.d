module dzero;

import core.stdc.stdio : FILE, fopen, fread, fclose, fseek, ftell, fclose, printf;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset, strcmp;
import std.stdio : writeln;
import std.zlib : uncompress;
import std.stdio : writeln;

enum ENCODE_SEPARATOR = ',';
enum ENCODE_STRUCT = '$';
enum ENCODE_SLICE = '*';
enum ENCODE_INSITU_STRUCT = '^';
enum ENCODE_ARRAY = '[';

struct SaferRawSlice(T) {
    T[] data;
    bool _valid;
    bool _secret;

    @disable this();

    this(T* ptr, size_t length) @nogc nothrow {
        this(ptr, length, false);
    }

    this(T* ptr, size_t length, bool secret) @nogc nothrow {
        data = ptr[0 .. length];
        _valid = true;
        _secret = secret;
    }

    ~this() @nogc nothrow {
        if (data.ptr !is null) {
            free(data.ptr);
            printf("SaferRawSlice: freed buffer");

            if(_secret) {
                memset(data.ptr, 0, data.length * T.sizeof);
                printf(" and memory sanitised");
            }

            printf("\n");
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
}

extern(C) nothrow @nogc int posix_memalign(void** memptr, size_t alignment, size_t size);

SaferRawSlice!ubyte loadBinary(const char* fileName) @nogc nothrow {
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

    // allocate buffer
    void* ptr;
    int res = posix_memalign(&ptr, 16, cast(size_t) fileSize);
    if (res != 0 || ptr is null)
    assert(0, "posix_memalign failed");

    ubyte* buffer = cast(ubyte*) ptr; // 64-byte alignment, 1024 bytes
    scope(exit) {
        //free(buffer);
        printf("Returning from loadBinary - malloced memory is automatically managed via SaferRawSlice\n");
    }
    if (buffer is null) {
        printf("buffer was null");
        fclose(file);
        return SaferRawSlice!ubyte.empty();
    }

    // read file contents
    size_t readSize = fread(buffer, 1, cast(size_t) fileSize, file);
    fclose(file);
    if (readSize != cast(size_t) fileSize) {
        free(buffer);
        return SaferRawSlice!ubyte.empty();
    }

    return SaferRawSlice!ubyte(buffer, readSize);
}

T* flatBufferFromBinary(T)(ubyte[] rawData) @nogc nothrow {
    auto blobPtr = processFlatBuffer(rawData.ptr, rawData.length);
    auto offset = cast(size_t)(blobPtr - rawData.ptr);
    auto blob = rawData[offset .. $];
    return cast(T*)(blob.ptr);
}

ubyte* processFlatBuffer(ubyte* data, size_t dataLength) @nogc nothrow {
    /*
        .------------------- HEADER ---------------------.
        | 0       magic "VBUF" 0x46554256                |
        | 4       version (1)                            |
        | 5       flags (1 = compressed)                 |
        | 6       struct encoding length N (=4k)         |
        | 8       number of offsets M                    |
        | 12      struct encoding data (4-bytes aligned) |
        | ...                                            |
        | 12+N    offset 1                               |
        | 20      offset 2                               |
        | ...                                            |
        | 12+N+4M offset M                               |
        |-------------- DATA ----------------------------|
        | 16+4N   blob (possibly compressed)             |
        | ...                                            |
        `------------------------------------------------`
     */

    int magic = cast(int)(data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24));
    if (magic != 0x46554256) {
        printf("Incorrect view buffer format");
        return null;
    }

    int viewBufferVersion = cast(int)data[4];
    if (viewBufferVersion != 1) {
        printf("Unknown view buffer version: %i", viewBufferVersion);
        return null;
    }

    ubyte flags = cast(ubyte)data[5];
    bool compressed = flags & 1 ? true : false;
    bool encodingPresent = flags & 2 ? true : false;
    bool encodingVersionHashPresent = flags & 4 ? true : false;

    if(compressed) printf("Data is compressed\n"); else printf("Data is not compressed\n");

    short userDefinedVersion = cast(short)(data[6] | (data[7] << 8));
    printf("User defined schema version: %d\n", userDefinedVersion);

    int dynamicIndex = 8;
    if(encodingVersionHashPresent) {
        printf("Schema version hash: ");
        for(; dynamicIndex < 24; dynamicIndex++) printf("%02x", data[dynamicIndex]);
        printf("\n");
    }
    else printf("No schema version hash found\n");

    if(encodingPresent) {
        short structEncodingLength = cast(short)(data[dynamicIndex++] | (data[dynamicIndex++] << 8));
        printf("struct encoding length %d\n", structEncodingLength);
        string structEncoding = cast(string)data[dynamicIndex .. dynamicIndex + structEncodingLength];
        generateStructs(structEncoding);
        dynamicIndex += structEncodingLength;
    }

    // get number of offsets to update
    int numOffsets = cast(int)(
        data[dynamicIndex++] |
            (data[dynamicIndex++] << 8) |
            (data[dynamicIndex++] << 16) |
            (data[dynamicIndex++] << 24)
    );

    // compute base pointer as a size_t
    int offsetsStart = dynamicIndex; // 12 + structEncodingLength;
    int dataOffset = offsetsStart + 4 * numOffsets;

    ubyte* blob = data + dataOffset;
    size_t base = cast(size_t) blob;

    // determine slice layout
    size_t ptrOffset = getSliceLayout();

    // update all offsets to be pointers
    for (int index = offsetsStart; index < dataOffset; index += 4) {
        int offset = data[index] | (data[index + 1] << 8) | (data[index + 2] << 16) | (data[index + 3] << 24);

        size_t* p = cast(size_t*)(blob + offset);
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
    printf("DONE!\n");

    return blob;
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
    switch(code) {
        case "st":
            return "immutable(char)";
        case "i1":
            return "ubyte";
        case "i2":
            return "short";
        case "i4":
            return "int";
        case "f4":
            return "float";
        case "bl":
            return "bool";
        case "bp":
            return "ubyte*";
        default:
            return code;
    }
}

ubyte[] decompress(ubyte[] compressedBytes) {
    // `uncompress` returns void[], cast to ubyte[]
    ubyte[] decompressed = cast(ubyte[]) uncompress(cast(void[]) compressedBytes);
    writeln("Decompressed size: ", decompressed.length);
    return decompressed;
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

//unittest {
//    struct Fruit {
//        string id;
//        int size;
//
//        ubyte[] bytes;
//    }
//
//    struct FruitBasket {
//        string title;
//        string subTitle;
//        string footer;
//
//        Fruit[] fruits;
//    }
//
//    //SFruit,stid,insize,ub[bytes,SFruitBasket,sttitle,stsubTitle,stfooter, SFruit[fruits,
//    //S1,st,in,ub[,S2,st,st,st, S1[,
//
//    auto rawData = loadBinary("../../data/fruits.bin");
//    if(!rawData.valid()) {
//        printf("Could not load the buffer\n");
//        return;
//    }
//    auto fb = flatBufferFromBinary!FruitBasket(rawData.slice());
//
//    if(fb is null) {
//        printf("error viewing buffer");
//        return;
//    }
//
//    // print stuff
//    printf("title = %s\n", fb.title.ptr);
//    printf("subtitle = %s\n", fb.subTitle.ptr);
//    printf("footer = %s\n", fb.footer.ptr);
//
//    printf("fruits.length = %zu\n", fb.fruits.length);
//}

unittest {
    struct Colour {
        float r;
        float g;
        float b;
    }

    struct Layer {
        immutable(char)[] id;
        bool visible;
        int rows;
        int cols;
        ubyte[] compressedBytes;
        ubyte[] decompressedBytes;
    }

    struct Level {
        immutable(char)[] id;
        Layer[] layers;
    }

    struct World {
        immutable(char)[] id;
        Level[] levels;
    }

    struct Element {
        immutable(char)[] id;
        immutable(char)[] type;
        immutable(char)[] cursor;
        int animId;
        int linkId;
        int fontAnimId;
        int widthSameAsScreenId;
        int heightSameAsScreenId;
        int padXSameAsScreenId;
        int padYSameAsScreenId;
        int relPosXSameAsScreenId;
        int relPosYSameAsScreenId;
        int relPosX2SameAsScreenId;
        int relPosY2SameAsScreenId;
        int widthSameAsId;
        int heightSameAsId;
        int padXSameAsId;
        int padYSameAsId;
        int relPosXSameAsId;
        int relPosYSameAsId;
        int relPosX2SameAsId;
        int relPosY2SameAsId;
        int fontColourIndex;
        int transition;
        int centreRow;
        int centreCol;
        bool autoAdjust;
        bool ar;
        bool active;
        bool clickable;
        bool disableCols;
        bool bHFade;
        bool bVFade;
        bool centreFont;
        float x;
        float y;
        float w;
        float h;
        float padx;
        float pady;
        float relposx;
        float relposy;
        float relposx2;
        float relposy2;
        float parallaxSpeed;
        float sparsityModulus;
        float sparsityParam;
        float offset;
        float parallaxZ;
        int[] strBytes;
    }

    struct Screen {
        immutable(char)[] id;
        Colour colour;
        Element[] elements;
    }

    struct Atlas {
        int width;
        int height;
        int size;
        ubyte[] bytes;
        float[] coords;
    }

    struct Frame {
        int atlas;
        int offset;
    }

    struct Anim {
        immutable(char)[] id;
        int spriteAtlas;
        int priority;
        int fps;
        int effects;
        int obj3dId;
        float widthInches;
        float cx;
        float cy;
        float radx;
        float rady;
        float aspectRatio;
        float progressOffset;
        Colour colour;
        Frame[] frames;
    }

    struct Sound {
        immutable(char)[] id;
        int size;
        ubyte[] compressedBytes;
        ubyte[] decompressedBytes;
    }

    struct Object3d {
        immutable(char)[] id;
        int numFaces;
        float[] normals;
        float[] texCoords;
        float[] positions;
    }

    struct Core {
        immutable(char)[] urlBase;
        immutable(char)[] getDataUrl;
        immutable(char)[] googelAccount;
        immutable(char)[] adUnitIdManifest;
        immutable(char)[] adUnitIdCode;
        immutable(char)[] adUnitDeviceId;
        World[] worlds;
        Screen[] screens;
        Atlas[] atlases;
        Anim[] anims;
        Sound[] sounds;
        Object3d[] obj3d;
    }

    import std.stdio;

    auto rawData = loadBinary("../../data/game.bin");
    if(!rawData.valid()) {
        printf("Could not load the buffer\n");
        return;
    }
    auto fb = flatBufferFromBinary!Core(rawData.slice());

    if(fb is null) {
        printf("error viewing buffer");
        return;
    }

    // decompress bytes into dummy slices !
    fb.sounds[0].decompressedBytes = decompress(fb.sounds[0].compressedBytes);
    fb.sounds[1].decompressedBytes = decompress(fb.sounds[1].compressedBytes);

    // print stuff
    writeln(*fb);
}

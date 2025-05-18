unittest {
    import ViewBuffer;
    import core.stdc.stdio : printf;

    struct Fruit {
        immutable(char)[] name;
        int weight;
        ubyte[] data;
    }

    struct Core {
        immutable(char)[] title;
        immutable(char)[] subtitle;
        immutable(char)[] footer;
        Fruit[] fruits;
    }

    auto rawData = loadViewBuffer("../../data/fruits.bin");
    if(!rawData.valid()) {
        printf("Could not load the buffer\n");
        return;
    }
    auto fb = getViewBufferSliceAs!Core(rawData.slice());

    if(fb is null) {
        printf("error viewing buffer");
        return;
    }

    printf("Fruit title = %.*s\n", fb.title.length, fb.title.ptr);
    printf("Fruit subtitle = %.*s\n", fb.subtitle.length, fb.subtitle.ptr);
    printf("Fruit footer = %.*s\n", fb.footer.length, fb.footer.ptr);
    printf("fruits length = %d\n", fb.fruits.length);
}

unittest {
    import ViewBuffer;
    import core.stdc.stdio : printf;

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
        printf("len0 = %d\n", fb.packets[0].decompressedBytes.length);
    }
    else {
        import std.stdio;
        writeln(*fb);
    }
}

unittest {
    import ViewBuffer;
    import core.stdc.stdio : printf;

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
        printf("len0 = %d\n", fb.packets[0].decompressedBytes.length);
    }
    else {
        import std.stdio;
        writeln(*fb);
    }
}

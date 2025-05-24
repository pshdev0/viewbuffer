import ViewBuffer;
import core.stdc.string : memcmp;
import core.stdc.stdio : printf;

bool assertString(immutable(char)[] slice, size_t expectedLen, immutable(char)[] expected) @nogc nothrow {
    return slice.length == expectedLen &&
            memcmp(cast(const(void)*)slice.ptr, cast(const(void)*)expected.ptr, expectedLen) == 0;
}

unittest {
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
        assert(false);
    }
    auto fb = getViewBufferSliceAs!Core(rawData.slice());

    if(fb is null) {
        printf("error viewing buffer");
        assert(false);
    }

    assert(assertString(fb.title, 12, "Fruit Basket"));
    assert(assertString(fb.subtitle, 16, "Tropical Edition"));
    assert(assertString(fb.footer, 17, "Enjoy responsibly"));

    assert(fb.fruits.length == 2);

    auto f0 = fb.fruits[0];
    auto f1 = fb.fruits[1];

    assert(assertString(f0.name, 5, "apple"));
    assert(f0.weight == 150);
    assert(f0.data.length == 5);
    for (auto i = 1; i < 6; i++) assert(f0.data[i-1] == i);

    assert(assertString(f1.name, 6, "banana"));
    assert(f1.weight == 120);
    assert(f1.data.length == 2);
    assert(f1.data[0] == 8);
    assert(f1.data[1] == 13);
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
        printf("len0 = %d\n", cast(int)fb.packets[0].decompressedBytes.length);
    }
    else {
        import std.stdio;
        writeln(*fb);
    }

    // endpoint
    assert(assertString(fb.endpoint, 23, "https://iot.example.com"));

    // networks
    assert(fb.networks.length == 2);

    // Network 0
    auto net0 = fb.networks[0];
    assert(assertString(net0.id, 9, "Network_0"));
    assert(net0.devices.length == 1);
    auto dev0 = net0.devices[0];
    assert(assertString(dev0.id, 8, "Device_0"));
    assert(dev0.statusCode == 100);

    // Network 1
    auto net1 = fb.networks[1];
    assert(assertString(net1.id, 9, "Network_1"));
    assert(net1.devices.length == 1);
    auto dev1 = net1.devices[0];
    assert(assertString(dev1.id, 8, "Device_1"));
    assert(dev1.statusCode == 101);

    // dashboards
    assert(fb.dashboards.length == 1);
    auto db = fb.dashboards[0];
    assert(assertString(db.id, 13, "MainDashboard"));
    assert(db.theme.hue == 0.1f);
    assert(db.theme.saturation == 0.2f);
    assert(db.theme.brightness == 0.3f);

    // widget
    assert(db.widgets.length == 1);
    auto w = db.widgets[0];
    assert(assertString(w.id, 6, "Gauge1"));
    assert(assertString(w.type, 5, "gauge"));
    assert(w.enabled == true);
    assert(w.posX == 15.0f);
    assert(w.posY == 25.0f);

    // data blob
    assert(fb.dataBlobs.length == 1);
    auto blob = fb.dataBlobs[0];
    assert(blob.length == 256);
    assert(blob.compressedPayload.length > 0);

    // transform
    assert(fb.transforms.length == 1);
    auto tr = fb.transforms[0];
    assert(assertString(tr.id, 7, "FilterA"));
    assert(tr.priority == 5);
    assert(tr.steps.length == 3);
    for (size_t s = 0; s < 3; ++s) {
        assert(tr.steps[s].phase == cast(int)s);
        assert(tr.steps[s].durationMs == 100 * cast(int)s);
    }

    // packet
    assert(fb.packets.length == 1);
    auto pkt = fb.packets[0];
    assert(assertString(pkt.id, 4, "Pkt1"));
    assert(pkt.size == 16);
    assert(pkt.compressedBytes.length > 0);
    assert(pkt.decompressedBytes.length == 16);
}

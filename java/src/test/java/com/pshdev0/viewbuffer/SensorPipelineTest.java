package com.pshdev0.viewbuffer;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class SensorPipelineTest {

    @Test
    public void testWriteFlatBufferPipeline() {
        assertDoesNotThrow(() -> {
            // Build two Sensor Networks, each with one Device
            var networkArray = ViewBuffer.arrayOf("Network");
            for (int n = 0; n < 2; n++) {
                var network = ViewBuffer.struct("Network");
                network.addString("id", "Network_" + n);

                // Devices
                var deviceArray = ViewBuffer.arrayOf("Device");
                var device = ViewBuffer.struct("Device");
                device.addString("id", "Device_" + n);
                device.addInt32("statusCode", 100 + n);
                deviceArray.addArrayItem(device);

                network.addArraySlice("devices", deviceArray);
                networkArray.addArrayItem(network);
            }

            // One Dashboard with Theme + one Widget
            var dashboardArray = ViewBuffer.arrayOf("Dashboard");
            var dashboard = ViewBuffer.struct("Dashboard");
            dashboard.addString("id", "MainDashboard");

            var theme = ViewBuffer.struct("Theme");
            theme.addFloat32("hue", 0.1f);
            theme.addFloat32("saturation", 0.2f);
            theme.addFloat32("brightness", 0.3f);
            dashboard.addStruct("theme", theme);

            var widgetArray = ViewBuffer.arrayOf("Widget");
            var widget = ViewBuffer.struct("Widget");
            widget.addString("id", "Gauge1");
            widget.addString("type", "gauge");
            widget.addBool("enabled", true);
            widget.addFloat32("posX", 15.0f);
            widget.addFloat32("posY", 25.0f);
            widgetArray.addArrayItem(widget);

            dashboard.addArraySlice("widgets", widgetArray);
            dashboardArray.addArrayItem(dashboard);

            // One DataBlob (compressed)
            var blobArray = ViewBuffer.arrayOf("DataBlob");
            var blob = ViewBuffer.struct("DataBlob");
            blob.addInt32("length", 256);
            // raw payload (uncompressed) - not used directly
            var raw = ViewBuffer.byteArray(new byte[] {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15});
            blob.addArraySlice("compressedPayload", ViewBuffer.compress(raw));
            blobArray.addArrayItem(blob);

            // One Transform with nested Steps
            var transformArray = ViewBuffer.arrayOf("Transform");
            var transform = ViewBuffer.struct("Transform");
            transform.addString("id", "FilterA");
            transform.addInt32("priority", 5);
            var stepArray = ViewBuffer.arrayOf("Step");
            for (int s = 0; s < 3; s++) {
                var step = ViewBuffer.struct("Step");
                step.addInt32("phase", s);
                step.addInt32("durationMs", 100 * s);
                stepArray.addArrayItem(step);
            }
            transform.addArraySlice("steps", stepArray);
            transformArray.addArrayItem(transform);

            // One Packet with 16‐byte payload
            var packetArray = ViewBuffer.arrayOf("Packet");
            var packet = ViewBuffer.struct("Packet");
            packet.addString("id", "Pkt1");
            packet.addInt32("size", 16);
            var payload = ViewBuffer.byteArray(new byte[]{
                    42,42,42,42, 42,42,42,42, 42,42,42,42, 42,42,42,42
            });
            packet.addArraySlice("compressedBytes", ViewBuffer.compress(payload));
            packet.addNullPointerSlice("decompressedBytes", "ubyte");
            packetArray.addArrayItem(packet);

            // PipelineConfig (Core)
            var config = ViewBuffer.struct("PipelineConfig");
            config.addString("endpoint", "https://iot.example.com");
            config.addArraySlice("networks", networkArray);
            config.addArraySlice("dashboards", dashboardArray);
            config.addArraySlice("dataBlobs", blobArray);
            config.addArraySlice("transforms", transformArray);
            config.addArraySlice("packets", packetArray);

            // Write out
            config.writeBuffer("../data/pipeline.bin", (short) 1, true, true, true);
        });
    }

    @Test
    public void testReadFlatBufferPipeline() {
        assertDoesNotThrow(() -> {
            // your deserialization logic here…
        });
    }
}
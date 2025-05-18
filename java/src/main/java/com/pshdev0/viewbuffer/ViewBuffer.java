package com.pshdev0.viewbuffer;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BiConsumer;
import java.util.zip.Deflater;

public class ViewBuffer {

    public static final String ENCODE_STRUCT = "$";
    public static final String ENCODE_SEPARATOR = ",";
    public static final String ENCODE_SLICE = "*";
    public static final String ENCODE_ARRAY = "[";
    public static final String ENCODE_INSITU_STRUCT = "^";
    public static final String ENCODE_STRING = "st";
    public static final String ENCODE_INT8 = "i1";
    public static final String ENCODE_INT16 = "i2";
    public static final String ENCODE_INT32 = "i4";
    public static final String ENCODE_BYTE_POINTER_32 = "bp";
    public static final String ENCODE_FLOAT32 = "f4";
    public static final String ENCODE_BOOL = "bl";
    public static final String ENCODE_TAB = "   ";

    public static final int HEADER_VBUF_MAGIC = 0x46554256; // "VBUF"
    public static final int HEADER_FATBUFFER_VERSION = 1;

    public static final int HEADER_FLAG_COMPRESS_DATA = 1;
    public static final int HEADER_FLAG_INCLUDE_STRUCT_ENCODING = 2;
    public static final int HEADER_FLAG_INCLUDE_STRUCT_ENCODING_VERSION_HASH = 4;
    public static final int HEADER__TODO__COMPRESS_STRUCT_ENCODING = 8;

    enum Type { STRUCT, ARRAY }
    Type type;
    static int staticOffsetIndex = -1;
    static final HashMap<Integer, ViewBuffer> staticBuffers = new HashMap<>();
    String structString = "";

    ArrayList<Integer> bytes = new ArrayList<>();
    int bufferOffsetIndex;
    boolean locked = false;
    int arrayLength = 0;
    int maxAlignment = 0;

    private ViewBuffer(String id, Type bufferType) {
        type = bufferType;
        staticBuffers.put(staticOffsetIndex, this);
        bufferOffsetIndex = staticOffsetIndex--;
        if(id != null) structString += id;
    }

    public static ViewBuffer arrayOf(String id) { return new ViewBuffer(id, Type.ARRAY); }
    public static ViewBuffer struct(String id) { return new ViewBuffer(id != null ? ENCODE_STRUCT + id : null, Type.STRUCT); }
    public static ViewBuffer string(String stringBufferContents) {
        var bytesToAdd = stringBufferContents.getBytes();
        return buildArray(ENCODE_STRING, bytesToAdd.length, 1, (i, buf) -> buf.bytes.add(bytesToAdd[i] & 0xFF));
    }
    public static ViewBuffer byteArray(byte... bytesToAdd) {
        return buildArray(ENCODE_INT8, bytesToAdd.length, 1, (i, buf) -> buf.bytes.add(bytesToAdd[i] & 0xFF));
    }
    public static ViewBuffer shortArray(short... shortsToAdd) throws IllegalStateException {
        return buildArray(ENCODE_INT16, shortsToAdd.length, 2, (i, buf) -> buf.addInt16(null, shortsToAdd[i]));
    }
    public static ViewBuffer intArray(int... intsToAdd) {
        return buildArray(ENCODE_INT32,intsToAdd.length, 4, (i, buf) -> buf.addInt32(null, intsToAdd[i]));
    }
    public static ViewBuffer floatArray(float... floatsToAdd) {
        return buildArray(ENCODE_FLOAT32, floatsToAdd.length, 4, (i, buf) -> buf.addFloat32(null, floatsToAdd[i]));
    }

    private static ViewBuffer buildArray(String id, int count, int alignment, BiConsumer<Integer, ViewBuffer> addBytes) {
        var buffer = struct(null); // use STRUCT initially to disable ARRAY warnings
        for (int i = 0; i < count; i++) addBytes.accept(i, buffer);
        buffer.arrayLength = count;
        buffer.locked = true;
        buffer.maxAlignment = alignment;
        buffer.type = Type.ARRAY; // switch to ARRAY
        buffer.structString = id;
        return buffer;
    }

    public void addString(String id, String str) { addArraySlice(id, ViewBuffer.string(str)); }
    public void addBool(String id, boolean ... list) { for (var b : list) addBool(ENCODE_BOOL + id, b); }
    public void addInt32(String id, int ... list) { for (var i : list) addInt32(ENCODE_INT32 + id, i); }
    public void addFloat32(String id, float ... list) { for(var f : list) addFloat32(ENCODE_FLOAT32 + id, f); }

    public int addStruct(String id, ViewBuffer zcb) {
        var structName = zcb.structString.split(ENCODE_SEPARATOR)[0];
        return addBytes(ENCODE_INSITU_STRUCT +id + structName, zcb.maxAlignment, zcb.bytes.toArray(Integer[]::new));
    }

    public int addArraySlice(String id, ViewBuffer zcb) {
        var i = zcb.bufferOffsetIndex;
        return addBytes(ENCODE_SLICE + id + ENCODE_ARRAY + zcb.structString, 8, i, i, i, i, i, i, i, i, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    public int addInt8(String id, int value) {
        return addBytes(ENCODE_INT8 + id, 1, value & 255);
    }

    public int addInt32(String id, int value) {
        return addBytes(ENCODE_INT32 + id, 4, value & 255, (value >> 8) & 255, (value >> 16) & 255, (value >> 24) & 255);
    }

    public int addNullPointerSlice(String id, String type) {
        return addBytes(ENCODE_SLICE + id + ENCODE_ARRAY + type, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    public int addFloat32(String id, float value) {
        var bits = Float.floatToIntBits(value);
        return addBytes(ENCODE_FLOAT32 + id, 4, bits & 255, (bits >> 8) & 255, (bits >> 16) & 255, (bits >> 24) & 255);
    }

    public int addInt16(String id, int value) {
        return addBytes(ENCODE_INT16 + id, 2, value & 255, (value >> 8) & 255);
    }

    public int addBool(String id, boolean value) {
        return addBytes(ENCODE_BOOL + id, 1, value ? 1 : 0);
    }

    private int addBytes(String id, int alignment, Integer ... bytesToAdd) {
        if(type.equals(Type.ARRAY)) throw new IllegalStateException("Warning - illegal operation on array buffer");
        if(locked) throw new IllegalStateException("Cannot alter locked buffers - switch your addition order");
        alignTo(alignment);
        int startIndex = bytes.size();
        bytes.addAll(Arrays.asList(bytesToAdd));
        if(id != null) structString += ENCODE_SEPARATOR + id;
        return startIndex;
    }

    public void addArrayItem(ViewBuffer zcb) {
        if(!type.equals(Type.ARRAY)) throw new IllegalStateException("Warning - this buffer is not an array - use ZeroCopyStruct.array()");
        if(maxAlignment > 0 && zcb.maxAlignment != maxAlignment) {
            throw new IllegalStateException("The buffer you are adding to this array has a different alignment to a previously added element");
        }
        alignTo(zcb.maxAlignment);
        bytes.addAll(zcb.bytes);
        arrayLength++;
        zcb.locked = true; // once a buffers bytes are added they cannot be altered
    }

    private void alignTo(int alignment) {
        if(maxAlignment < alignment) maxAlignment = alignment;
        while (bytes.size() % alignment > 0) bytes.add(0);
    }

    public void reset() {
        // todo - clear everything
        //        in the calling program we may need to create a new buffer!
    }

    public String generateStructs(String structEncoding) {
        var types = Map.of(
                ENCODE_STRING, "immutable(char)",
                ENCODE_INT8, "ubyte",
                ENCODE_INT16, "short",
                ENCODE_INT32, "int",
                ENCODE_FLOAT32, "float",
                ENCODE_BOOL, "bool",
                ENCODE_BYTE_POINTER_32, "ubyte*"
        );

        var tokens = structEncoding.split(ENCODE_SEPARATOR);
        tokens[tokens.length - 1] = tokens[tokens.length - 1].trim(); // the last token could have padding
        StringBuilder code = new StringBuilder();
        var structOpen = false;
        for (var t : tokens) {
            switch(t.substring(0, 1)) {
                case ENCODE_STRUCT -> { // struct
                    if(structOpen) code.append("}\n\n");
                    code.append("struct ").append(t.substring(1)).append(" {\n");
                    structOpen = true;
                }
                case ENCODE_SLICE -> { // slice
                    var index = t.indexOf(ENCODE_ARRAY);
                    if (index == -1) throw new IllegalStateException("Malformed token: " + t);
                    var name = t.substring(1, index);
                    var type = t.substring(index + 1);
                    code.append(structOpen ? ENCODE_TAB : "")
                            .append(types.getOrDefault(type, type)).append("[] ").append(name).append(";\n");
                }
                case ENCODE_INSITU_STRUCT -> { // add struct in-situ (insert data)
                    var index = t.indexOf(ENCODE_STRUCT);
                    if (index == -1) throw new IllegalStateException("Malformed token: " + t);
                    var varName = t.substring(1, index);
                    var structName = t.substring(index + 1);
                    code.append(structOpen ? ENCODE_TAB : "").append(structName).append(" ").append(varName).append(";\n");
                }
                default -> {
                    var x = t.substring(0, 2);
                    code.append(structOpen ? ENCODE_TAB : "").append(types.getOrDefault(x, x)).append(" ")
                            .append(t.substring(2)).append(";\n");
                }
            }
        }
        if(structOpen) code.append("}\n");
        return code.toString();
    }

    public ByteBuffer asByteBuffer(short userDefinedVersion, boolean includeStructEncoding, boolean includeStructEncodingVersionHash, boolean compressBlob) {
        final var structEncoding = getStructEncodingString();
        System.out.println(generateStructs(structEncoding));

        /*
         * build the data blob first
         */
        HashMap<Integer, Integer> offsetIndexPositions = new HashMap<>();
        List<Integer> buffersToAdd = new ArrayList<>();
        buffersToAdd.add(bufferOffsetIndex);
        var blob = arrayOf(null);

        // build the linear blob, recording the data start positions of each offset
        while(!buffersToAdd.isEmpty()) {
            int prevBlobSize = blob.size();
            for(var oi : buffersToAdd) {
                offsetIndexPositions.put(oi, blob.size());
                blob.bytes.addAll(staticBuffers.get(oi).bytes);
//                blob.alignTo(4);
            }
            AtomicInteger index = new AtomicInteger();
            buffersToAdd = blob.bytes.stream()
                    .filter(x -> index.getAndIncrement() >= prevBlobSize && x < 0)
                    .distinct().toList();
        }

        // now go through the whole blob, replacing negative offset entries with data start positions
        ArrayList<Integer> locationsWhereBaseShouldBeAdded = new ArrayList<>();
        for(var index = 0; index < blob.size() ; index++) {
            // replace offset with pointer offset
            var v = blob.bytes.get(index);
            if(v < 0) {
                locationsWhereBaseShouldBeAdded.add(index);
                blob.setInt32Index(index, offsetIndexPositions.get(v)); // write the slice offset
                blob.setInt32Index(index + 4, 0); // 4GB max offset since top 4 bytes are set to 0
                blob.setInt32Index(index + 8, staticBuffers.get(v).arrayLength); // write the slice length
                blob.setInt32Index(index + 12, 0); // max length 2,147,483,647, or double this?
                index += 15; // the for loop will do the 1 extra step to 16 bytes
            }
        }

        if(!blob.bytes.stream().filter(x -> x < 0 || x > 255).toList().isEmpty()) throw new IllegalStateException("Invalid blob value found");

        /*
            build the header second
         */
        var header = struct(null);

        // ViewBuffer magic + version
        header.addInt32(null, HEADER_VBUF_MAGIC);
        header.addInt8(null, HEADER_FATBUFFER_VERSION); // version 1

        // flags
        int flags = 0;
        flags |= compressBlob ? HEADER_FLAG_COMPRESS_DATA : 0;
        flags |= includeStructEncoding ? HEADER_FLAG_INCLUDE_STRUCT_ENCODING : 0;
        flags |= includeStructEncodingVersionHash ? HEADER_FLAG_INCLUDE_STRUCT_ENCODING_VERSION_HASH : 0;
        header.addInt8(null, flags); // not compressed, includes encoding and encoding hash

        // user-defined blob version number
        header.addInt16(null, userDefinedVersion);

        // header, compressed file size, decompressed file size (compressed blob size may be same as final blob size)
        var HEADER_SIZE_POST_FILL_OFFSET = header.addInt32(null, 0); // header file size - post filled later
        var COMPRESSED_BLOB_SIZE_POST_FILL_OFFSET = header.addInt32(null, 0); // compressedBlobFileSize - post filled later
        var FINAL_BLOB_SIZE_POST_FILL_OFFSET = header.addInt32(null, 0); // decompressedBlobFileSize - post filled later

        // struct encoding hash
        if(includeStructEncodingVersionHash) {
            try {
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                byte[] fullHash = digest.digest(structEncoding.getBytes(StandardCharsets.UTF_8));
                byte[] hash16 = Arrays.copyOf(fullHash, 16);
                StringBuilder hex = new StringBuilder();
                for (byte b : hash16) hex.append(String.format("%02x", b));
                System.out.println("Struct encoding version: " + hex);
                for (byte b : hash16) header.addInt8(null, b); // or header.addByte(null, b) depending on your API
            } catch (Exception e) {
                throw new RuntimeException("Hashing failed", e);
            }
        }

        // struct encoding
        if (includeStructEncoding) {
            header.addInt16(null, structEncoding.length()); // length of struct encoding
            for (var c : structEncoding.getBytes(StandardCharsets.UTF_8)) header.addInt8(null, c);
        }

        // # offsets to store + offsets
        header.addInt32(null, locationsWhereBaseShouldBeAdded.size());
        for(var offset : locationsWhereBaseShouldBeAdded) header.addInt32(null, offset);

        // sanity check
        if(!header.bytes.stream().filter(x -> x < 0 || x > 255).toList().isEmpty()) throw new IllegalStateException("Invalid header value found");

        // post fill the header, blob, and compressed blob sizes if present
        header.setInt32Index(HEADER_SIZE_POST_FILL_OFFSET, header.size());
        header.setInt32Index(FINAL_BLOB_SIZE_POST_FILL_OFFSET, blob.size());
        if(compressBlob) blob = ViewBuffer.compress(blob);
        header.setInt32Index(COMPRESSED_BLOB_SIZE_POST_FILL_OFFSET, blob.size());

        /*
            combine the header + blob
         */
        ByteBuffer out = ByteBuffer.allocate(header.size() + blob.size()); // write the bytes out
        header.bytes.forEach(x -> out.put((byte)(x & 255)));
        blob.bytes.forEach(x -> out.put((byte)(x & 255)));

        System.out.println("Header (" + header.size() + " bytes), blob (" + blob.size() + " bytes), total (" + (header.size() + blob.size()) + " bytes)");

        return out.flip();
    }

    private static String getStructEncodingString() {
        StringBuilder structEncodingBuilder = new StringBuilder();
        Set<String> seen = new HashSet<>();

        for (var buffer : staticBuffers.values()) {
            var s = buffer.structString;
            if (s.startsWith(ENCODE_STRUCT) && seen.add(s)) { // add() returns false if already present
                if (!structEncodingBuilder.isEmpty()) structEncodingBuilder.append(ENCODE_SEPARATOR);
                structEncodingBuilder.append(s);
            }
        }
        while(structEncodingBuilder.length() % 4 != 2) structEncodingBuilder.append(" "); // ensure 4-byte alignment - use != 2 since the length is 2-bytes and we're not aligned to 4 bytes at that point
        var structEncoding = structEncodingBuilder.toString();
        return structEncoding;
    }

    private void setInt32Index(int index, int value) {
        for (int i = 0; i < 4; i++) bytes.set(index + i, (value >> (8 * i)) & 0xFF);
    }

    int size() { return bytes.size(); }

    public void writeBuffer(String outFilePath, short userDefinedVersionNumber,
                            boolean includeStructEncoding,
                            boolean includeStructEncodingVersionHash,
                            boolean compressBlob) {
        var out = asByteBuffer(userDefinedVersionNumber, includeStructEncoding, includeStructEncodingVersionHash, compressBlob);
        Path filePath = Path.of(outFilePath);

        try {
            Files.createDirectories(filePath.getParent());
            try (FileChannel channel = FileChannel.open(
                    filePath, StandardOpenOption.CREATE, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING)) {
                int totalBytesWritten = 0;
                while (out.hasRemaining()) {
                    int bytesWritten = channel.write(out);
                    if (bytesWritten < 0) throw new IOException("Failed to write data to the file.");
                    totalBytesWritten += bytesWritten;
                }
                System.out.println("File written successfully! Total bytes written: " + totalBytesWritten);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public static ViewBuffer compress(ViewBuffer buffer) {
        var data = new byte[buffer.bytes.size()];
        for (var c1 = 0; c1 < buffer.bytes.size(); c1++) {
            data[c1] = (byte)(buffer.bytes.get(c1) & 0xFF);
        }
        Deflater deflater = new Deflater();
        deflater.setInput(data);
        deflater.finish();

        byte[] outBuffer = new byte[1024];
        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();

        while (!deflater.finished()) {
            int count = deflater.deflate(outBuffer);
            outputStream.write(outBuffer, 0, count);
        }

        var compressedBytes = outputStream.toByteArray();
        System.out.println("Compressed to " + (outputStream.size() / (float)data.length) * 100 + "% of original size");

        return ViewBuffer.byteArray(compressedBytes);
    }
}

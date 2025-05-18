package com.pshdev0.viewbuffer;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class FruitTest {

    @Test
    public void testWriteFlatBuffer() {
        assertDoesNotThrow(() -> {
            var appleData = ViewBuffer.byteArray(new byte[] { 1, 2, 3, 4, 5 });
            var bananaData = ViewBuffer.byteArray(new byte[] { 8, 13 });

            var apple = ViewBuffer.struct("Fruit");
            apple.addString("name", "apple");
            apple.addInt32("weight", 150); // weight in grams
            apple.addArraySlice("data", appleData);

            var banana = ViewBuffer.struct(null);
            banana.addString(null, "banana");
            banana.addInt32(null, 120); // weight in grams
            banana.addArraySlice(null, bananaData);

            var fruitsArray = ViewBuffer.arrayOf("Fruit");
            fruitsArray.addArrayItem(apple);
            fruitsArray.addArrayItem(banana);

            var core = ViewBuffer.struct("Core");
            core.addString("title", "Fruit Basket"); // title
            core.addString("subtitle", "Tropical Edition"); // subtitle
            core.addString("footer", "Enjoy responsibly"); // footer
            core.addArraySlice("fruits", fruitsArray);  // fruit array

            short version = 1;
            boolean encodeStruct = true;
            boolean includeStructHash = true;
            boolean compressBlob = true;
            core.writeBuffer("../data/fruits.bin", version, encodeStruct, includeStructHash, compressBlob);
        });
    }

    @Test
    public void testReadFlatBuffer() {
        assertDoesNotThrow(() -> {
            // todo
        });
    }
}

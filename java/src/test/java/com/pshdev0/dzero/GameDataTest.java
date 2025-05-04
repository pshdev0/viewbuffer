package com.pshdev0.dzero;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

public class GameDataTest {

    @Test
    public void testWriteFlatBuffer() {
        assertDoesNotThrow(() -> {
            // build worlds and levels
            var worldArray = ViewBuffer.arrayOf("World");
            var numDummyWorlds = 2;
            for (var worldId = 0; worldId < numDummyWorlds; worldId++) {
                var world = ViewBuffer.struct("World");
                world.addString("id", "Test World xxx " + worldId);

                var levelArray = ViewBuffer.arrayOf("Level");

                int numDummyLevels = 2;
                for (var levelId = 0; levelId < numDummyLevels; levelId++) {

                    var level = ViewBuffer.struct("Level");
                    level.addString("id", "Level xyz " + levelId);

                    // we can do away with many of the "data" classes - the relevant ones are actually in the .autogen package (?)

                    var layerArray = ViewBuffer.arrayOf("Layer");

                    int numDummyLayers = 2;
                    for(var layerId = 0; layerId < numDummyLayers; layerId++) {   // (we flatten the 2d array to 1d)

                        int numDummyExportValues = 32;
                        var temp = new short[numDummyExportValues];
                        for (var exportValue = 0; exportValue < numDummyExportValues; exportValue++) {
                            temp[exportValue] = ((Integer)exportValue).shortValue();
                        }
                        var bytesDataArray = ViewBuffer.shortArray(temp);

                        var layerItem = ViewBuffer.struct("Layer");
                        layerItem.addString("id", "Dummy layer " + layerId);
                        layerItem.addBool("visible", layerId % 2 == 0);
                        layerItem.addInt32("rows", 123);
                        layerItem.addInt32("cols", 123);
                        layerItem.addArraySlice("compressedBytes", ViewBuffer.compress(bytesDataArray));
                        layerItem.addNullPointerSlice("decompressedBytes", "ubyte");
                        layerArray.addArrayItem(layerItem);
                    }
                    level.addArraySlice("layers", layerArray);

                    levelArray.addArrayItem(level);
                }
                world.addArraySlice("levels", levelArray);

                worldArray.addArrayItem(world);
            }

            // build screens
            var screenArray = ViewBuffer.arrayOf("Screen");
            var numDummyScreens = 1;
            for(int screenId = 0; screenId < numDummyScreens; screenId++) {
                var screenBuffer = ViewBuffer.struct("Screen");
                screenBuffer.addString("id", "Dummy Screen " + screenId); // id

                var color = ViewBuffer.struct("Colour");
                color.addFloat32("r", 0.2f);
                color.addFloat32("g", 0.4f);
                color.addFloat32("b", 0.6f);
                screenBuffer.addStruct("colour", color);

                var elementArray = ViewBuffer.arrayOf("Element");

                var numDummyScreenElements = 1;
                for(var screenElementId = 0; screenElementId < numDummyScreenElements; screenElementId++) {
                    var elementBuffer = ViewBuffer.struct("Element");

                    elementBuffer.addString("id", "Dummy Element " + screenElementId);
                    elementBuffer.addString("type", "abc");
                    elementBuffer.addString("cursor", "def");

                    elementBuffer.addInt32("animId", 1);
                    elementBuffer.addInt32("linkId", 2);
                    elementBuffer.addInt32("fontAnimId", 3);
                    elementBuffer.addInt32("widthSameAsScreenId", 4);
                    elementBuffer.addInt32("heightSameAsScreenId", 5);
                    elementBuffer.addInt32("padXSameAsScreenId", 6);
                    elementBuffer.addInt32("padYSameAsScreenId", 7);
                    elementBuffer.addInt32("relPosXSameAsScreenId", 8);
                    elementBuffer.addInt32("relPosYSameAsScreenId", 9);
                    elementBuffer.addInt32("relPosX2SameAsScreenId", 10);
                    elementBuffer.addInt32("relPosY2SameAsScreenId", 11);
                    elementBuffer.addInt32("widthSameAsId", 12);
                    elementBuffer.addInt32("heightSameAsId", 13);
                    elementBuffer.addInt32("padXSameAsId", 14);
                    elementBuffer.addInt32("padYSameAsId", 15);
                    elementBuffer.addInt32("relPosXSameAsId", 16);
                    elementBuffer.addInt32("relPosYSameAsId", 17);
                    elementBuffer.addInt32("relPosX2SameAsId", 18);
                    elementBuffer.addInt32("relPosY2SameAsId", 19);
                    elementBuffer.addInt32("fontColourIndex", 20);
                    elementBuffer.addInt32("transition", 21);
                    elementBuffer.addInt32("centreRow", 22);
                    elementBuffer.addInt32("centreCol", 23);

                    elementBuffer.addBool("autoAdjust", true);
                    elementBuffer.addBool("ar", false);
                    elementBuffer.addBool("active", true);
                    elementBuffer.addBool("clickable", false);
                    elementBuffer.addBool("disableCols", true);
                    elementBuffer.addBool("bHFade", false);
                    elementBuffer.addBool("bVFade", true);
                    elementBuffer.addBool("centreFont", false);

                    elementBuffer.addFloat32("x", 1);
                    elementBuffer.addFloat32("y", 2);
                    elementBuffer.addFloat32("w", 3);
                    elementBuffer.addFloat32("h", 4);
                    elementBuffer.addFloat32("padx", 5);
                    elementBuffer.addFloat32("pady", 6);
                    elementBuffer.addFloat32("relposx", 7);
                    elementBuffer.addFloat32("relposy", 8);
                    elementBuffer.addFloat32("relposx2", 9);
                    elementBuffer.addFloat32("relposy2", 10);
                    elementBuffer.addFloat32("parallaxSpeed", 11);
                    elementBuffer.addFloat32("sparsityModulus", 12);
                    elementBuffer.addFloat32("sparsityParam", 13);
                    elementBuffer.addFloat32("offset", 14);
                    elementBuffer.addFloat32("parallaxZ", 15);

                    var bytes = ViewBuffer.intArray(1, 2, 3, 4, 5, 6);
                    elementBuffer.addArraySlice("strBytes", bytes);

                    elementArray.addArrayItem(elementBuffer);
                }

                screenBuffer.addArraySlice("elements", elementArray);

                screenArray.addArrayItem(screenBuffer);
            }

            // build atlases
            var atlasArray = ViewBuffer.arrayOf("Atlas");
            var numDummySpriteAtlas = 3;
            for(var spriteAtlasId = 0; spriteAtlasId < numDummySpriteAtlas; spriteAtlasId++) {
                var atlasBuffer = ViewBuffer.struct("Atlas");
                atlasBuffer.addInt32("width", 800 + spriteAtlasId);
                atlasBuffer.addInt32("height", 600 + spriteAtlasId);
                atlasBuffer.addInt32("size", 10);

                var imageBytesArray = ViewBuffer.byteArray(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }); // todo - maybe deflate this, not sure since can just use flat buffer data?
                var coordsArray = ViewBuffer.floatArray(1, 2, 3, 4, 5, 6);

                atlasBuffer.addArraySlice("bytes", imageBytesArray);
                atlasBuffer.addArraySlice("coords", coordsArray);

                atlasArray.addArrayItem(atlasBuffer);
            }

            // build anims
            var animArray = ViewBuffer.arrayOf("Anim");
            var numDummyAnims = 1;
            for(var animId = 0; animId < numDummyAnims; animId++) {
                var animBuffer = ViewBuffer.struct("Anim");
                animBuffer.addString("id", "Dummy Anim " + animId);
                animBuffer.addInt32("spriteAtlas",1);
                animBuffer.addInt32("priority",100);
                animBuffer.addInt32("fps",32);
                animBuffer.addInt32("effects",255);
                animBuffer.addInt32("obj3dId",51);
                animBuffer.addFloat32("widthInches", 10);
                animBuffer.addFloat32("cx", 20);
                animBuffer.addFloat32("cy", 30);
                animBuffer.addFloat32("radx", 40);
                animBuffer.addFloat32("rady", 50);
                animBuffer.addFloat32("aspectRatio", 60);
                animBuffer.addFloat32("progressOffset", 70);

                var color = ViewBuffer.struct("Colour");
                color.addFloat32("r", 10);
                color.addFloat32("g", 20);
                color.addFloat32("b", 30);
                animBuffer.addStruct("colour", color);

                var frameArray = ViewBuffer.arrayOf("Frame");
                var numDummyFrame = 7;
                for (var frameId = 0; frameId < numDummyFrame; frameId++) {
                    var frameBuffer = ViewBuffer.struct("Frame");
                    frameBuffer.addInt32("atlas",0);
                    frameBuffer.addInt32("offset",frameId);
                    frameArray.addArrayItem(frameBuffer);
                }
                animBuffer.addArraySlice("frames", frameArray);

                animArray.addArrayItem(animBuffer);
            }

            // build sounds
            var soundArray = ViewBuffer.arrayOf("Sound");
            var numDummySounds = 2;
            for(var soundId = 0; soundId < numDummySounds; soundId++) {
                var soundBuffer = ViewBuffer.struct("Sound");
                soundBuffer.addString("id", "Dummy Sound " + soundId);
                soundBuffer.addInt32("size", 7);

                var bytesBuffer = ViewBuffer.byteArray(new byte[] { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 });
                soundBuffer.addArraySlice("compressedBytes", ViewBuffer.compress(bytesBuffer));
                soundBuffer.addNullPointerSlice("decompressedBytes", "ubyte");

                soundArray.addArrayItem(soundBuffer);
            }

            // 3d objects
            var obj3dArray = ViewBuffer.arrayOf("Object3d");
            var numDummySpriteModels = 2;
            for(var spriteModelId = 0; spriteModelId < numDummySpriteModels; spriteModelId++) {
                var obj3d = ViewBuffer.struct("Object3d");
                obj3d.addString("id", "Sprite Model " + spriteModelId);
                obj3d.addInt32("numFaces", 3);
                obj3d.addArraySlice("normals", ViewBuffer.floatArray(1, 2, 3));
                obj3d.addArraySlice("texCoords", ViewBuffer.floatArray(10, 20, 30));
                obj3d.addArraySlice("positions", ViewBuffer.floatArray(15, 30, 45));
                obj3dArray.addArrayItem(obj3d);
            }

            var core = ViewBuffer.struct("Core");
            core.addString("urlBase", "dummy string 1");
            core.addString("getDataUrl", "dummy string 2");
            core.addString("googelAccount", "dummy string 3");
            core.addString("adUnitIdManifest", "dummy string 4");
            core.addString("adUnitIdCode", "dummy string 5");
            core.addString("adUnitDeviceId", "dummy string 6");
            core.addArraySlice("worlds", worldArray);
            core.addArraySlice("screens", screenArray);
            core.addArraySlice("atlases", atlasArray);
            core.addArraySlice("anims", animArray);
            core.addArraySlice("sounds", soundArray);
            core.addArraySlice("obj3d", obj3dArray);

            short version = 1;
            boolean encodeStruct = true;
            boolean includeStructHash = true;
            core.writeBuffer("../data/game.bin", version, encodeStruct, includeStructHash);
        });
    }

    @Test
    public void testReadFlatBuffer() {
        assertDoesNotThrow(() -> {
            // todo
        });
    }
}

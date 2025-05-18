export D_COMPILER=ldc2
export CC=clang
export CXX=clang++

dub clean
dub build
dub run

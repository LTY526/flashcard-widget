//
//  BridgingHeader.h
//  flashcard-widget
//
//  Exposes the vendored zstd decompression-only C library to Swift.
//  zstd is required because `.anki21b` collection containers (the format
//  most current Anki exports use) are zstd-compressed, and Apple's
//  Compression framework does not implement the zstd algorithm.
//

#import "ThirdParty/zstd/lib/zstd.h"

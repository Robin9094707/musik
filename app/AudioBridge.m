#import "AudioBridge.h"
@import CSFBAudioEngine;

@interface SMAudioEngine () <SFBAudioPlayerDelegate>
@property(nonatomic, strong) SFBAudioPlayer *player;
@end
@implementation SMAudioEngine
- (instancetype)init { if ((self = [super init])) { _player = [SFBAudioPlayer new]; _player.delegate = self; } return self; }
- (BOOL)startURL:(NSURL *)url error:(NSError **)error { return [_player playURL:url error:error]; }
- (void)pause { [_player pause]; }
- (BOOL)resume:(NSError **)error { return [_player playReturningError:error]; }
- (void)stop { [_player stop]; }
- (BOOL)seek:(double)seconds { return [_player seekToTime:seconds]; }
- (double)time { double t = _player.currentTime; return isfinite(t) && t > 0 ? t : 0; }
- (double)duration { double t = _player.totalTime; return isfinite(t) && t > 0 ? t : 0; }
- (BOOL)playing { return _player.isPlaying; }
- (void)audioPlayerEndOfAudio:(SFBAudioPlayer *)audioPlayer {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onEnd) self.onEnd(); });
}
- (void)audioPlayer:(SFBAudioPlayer *)audioPlayer playbackStateChanged:(SFBAudioPlayerPlaybackState)state {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onState) self.onState(self.player.isPlaying); });
}
- (void)audioPlayer:(SFBAudioPlayer *)audioPlayer encounteredError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onError) self.onError(error.localizedDescription); });
}
- (void)audioPlayer:(SFBAudioPlayer *)audioPlayer decodingAborted:(id<SFBPCMDecoding>)decoder error:(NSError *)error framesRendered:(AVAudioFramePosition)framesRendered {
    [self audioPlayer:audioPlayer encounteredError:error];
}
@end

static NSDictionary *SMKeys(void) {
    return @{ @"title": SFBAudioMetadataKeyTitle, @"artist": SFBAudioMetadataKeyArtist,
        @"albumTitle": SFBAudioMetadataKeyAlbumTitle, @"albumArtist": SFBAudioMetadataKeyAlbumArtist,
        @"composer": SFBAudioMetadataKeyComposer, @"genre": SFBAudioMetadataKeyGenre,
        @"releaseDate": SFBAudioMetadataKeyReleaseDate, @"trackNumber": SFBAudioMetadataKeyTrackNumber,
        @"trackTotal": SFBAudioMetadataKeyTrackTotal, @"discNumber": SFBAudioMetadataKeyDiscNumber,
        @"discTotal": SFBAudioMetadataKeyDiscTotal, @"lyrics": SFBAudioMetadataKeyLyrics,
        @"bpm": SFBAudioMetadataKeyBPM, @"comment": SFBAudioMetadataKeyComment,
        @"grouping": SFBAudioMetadataKeyGrouping, @"isrc": SFBAudioMetadataKeyISRC };
}
@implementation SMTags
+ (NSArray<NSString *> *)extensions { return SFBAudioFile.supportedPathExtensions.allObjects; }
+ (BOOL)validateURL:(NSURL *)url error:(NSError **)error {
    SFBAudioDecoder *decoder = [[SFBAudioDecoder alloc] initWithURL:url error:error];
    if (!decoder || ![decoder openReturningError:error]) return NO;
    [decoder closeReturningError:nil];
    return YES;
}
+ (NSDictionary<NSString *,id> *)readURL:(NSURL *)url error:(NSError **)error {
    SFBAudioFile *file = [SFBAudioFile audioFileWithURL:url error:error];
    if (!file) return nil;
    SFBAudioMetadata *m = file.metadata;
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (NSString *key in @[@"title", @"artist", @"albumTitle", @"albumArtist", @"composer", @"genre", @"releaseDate", @"trackNumber", @"trackTotal", @"discNumber", @"discTotal", @"lyrics", @"bpm", @"comment", @"grouping", @"isrc"])
        if ([m objectForKey:SMKeys()[key]]) d[key] = [m objectForKey:SMKeys()[key]];
    d[@"duration"] = file.properties.duration ?: @0;
    d[@"sampleRate"] = file.properties.sampleRate ?: @0;
    d[@"bitDepth"] = file.properties.bitDepth ?: @0;
    d[@"format"] = file.properties.formatName ?: url.pathExtension.uppercaseString;
    SFBAttachedPicture *picture = [m attachedPicturesOfType:SFBAttachedPictureTypeFrontCover].firstObject ?: m.attachedPictures.anyObject;
    if (picture) d[@"artwork"] = picture.imageData;
    return d;
}
+ (BOOL)writeURL:(NSURL *)url values:(NSDictionary<NSString *,id> *)values error:(NSError **)error {
    SFBAudioFile *file = [SFBAudioFile audioFileWithURL:url error:error];
    if (!file) return NO;
    // Modify only the exposed fields; preserve other metadata and pictures.
    for (NSString *key in @[@"title", @"artist", @"albumTitle", @"albumArtist", @"composer", @"genre", @"releaseDate", @"trackNumber", @"trackTotal", @"discNumber", @"discTotal", @"lyrics", @"bpm", @"comment", @"grouping", @"isrc"]) {
        id value = values[key];
        if (value) [file.metadata setObject:(value == NSNull.null ? nil : value) forKeyedSubscript:SMKeys()[key]];
    }
    if (values[@"artwork"]) {
        [file.metadata removeAttachedPicturesOfType:SFBAttachedPictureTypeFrontCover];
        if ([values[@"artwork"] isKindOfClass:NSData.class])
            [file.metadata attachPicture:[[SFBAttachedPicture alloc] initWithImageData:values[@"artwork"] type:SFBAttachedPictureTypeFrontCover]];
    }
    return [file writeMetadataReturningError:error];
}
@end

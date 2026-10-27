#import "AudioBridge.h"
@import CSFBAudioEngine;

static BOOL SMUsesNativeDecoder(NSURL *url) {
    return [@[@"m4a", @"m4b", @"m4r", @"mp4", @"aac", @"caf", @"3gp"] containsObject:url.pathExtension.lowercaseString];
}
@interface SMAudioEngine () <SFBAudioPlayerDelegate, AVAudioPlayerDelegate>
@property(nonatomic, strong) SFBAudioPlayer *player;
@property(nonatomic, strong, nullable) AVAudioPlayer *nativePlayer;
@property(nonatomic) BOOL resumeAfterInterruption;
@end
@implementation SMAudioEngine
- (instancetype)init {
    if ((self = [super init])) {
        _player = [SFBAudioPlayer new]; _player.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (BOOL)startURL:(NSURL *)url error:(NSError **)error {
    [self stop];
    if (SMUsesNativeDecoder(url)) {
        self.nativePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:error];
        if (!self.nativePlayer) return NO;
        self.nativePlayer.delegate = self;
        if ([self.nativePlayer play]) return YES;
        if (error) *error = [NSError errorWithDomain:@"SimplexPlayback" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Audio playback could not start."}];
        return NO;
    }
    return [_player playURL:url error:error];
}
- (void)pause { if (self.nativePlayer) [self.nativePlayer pause]; else [_player pause]; }
- (BOOL)resume:(NSError **)error {
    if (self.nativePlayer) {
        if ([self.nativePlayer play]) return YES;
        if (error) *error = [NSError errorWithDomain:@"SimplexPlayback" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Audio playback could not resume."}];
        return NO;
    }
    return [_player playReturningError:error];
}
- (void)stop { [_nativePlayer stop]; _nativePlayer = nil; [_player stop]; }
- (BOOL)seek:(double)seconds { if (self.nativePlayer) { self.nativePlayer.currentTime = seconds; return YES; } return [_player seekToTime:seconds]; }
- (double)time { double t = self.nativePlayer ? self.nativePlayer.currentTime : _player.currentTime; return isfinite(t) && t > 0 ? t : 0; }
- (double)duration { double t = self.nativePlayer ? self.nativePlayer.duration : _player.totalTime; return isfinite(t) && t > 0 ? t : 0; }
- (BOOL)playing { return self.nativePlayer ? self.nativePlayer.isPlaying : _player.isPlaying; }
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    dispatch_async(dispatch_get_main_queue(), ^{ if (player == self.nativePlayer && self.onEnd) self.onEnd(); });
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onError) self.onError(error.localizedDescription); });
}
- (void)interruption:(NSNotification *)notification {
    if (!self.nativePlayer) return;
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
        self.resumeAfterInterruption = self.nativePlayer.isPlaying;
        [self.nativePlayer pause];
    } else {
        BOOL shouldResume = ([notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) != 0;
        if (shouldResume && self.resumeAfterInterruption) { [[AVAudioSession sharedInstance] setActive:YES error:nil]; [self.nativePlayer play]; }
        self.resumeAfterInterruption = NO;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onState) self.onState(self.playing); });
}
- (void)audioPlayerEndOfAudio:(SFBAudioPlayer *)audioPlayer {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.nativePlayer && self.onEnd) self.onEnd(); });
}
- (void)audioPlayer:(SFBAudioPlayer *)audioPlayer playbackStateChanged:(SFBAudioPlayerPlaybackState)state {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.nativePlayer && self.onState) self.onState(self.playing); });
}
- (void)audioPlayer:(SFBAudioPlayer *)audioPlayer encounteredError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.nativePlayer && self.onError) self.onError(error.localizedDescription); });
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
    if (SMUsesNativeDecoder(url)) return [[AVAudioFile alloc] initForReading:url error:error] != nil;
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

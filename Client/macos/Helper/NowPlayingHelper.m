// Reads macOS's "Now Playing" (MediaRemote) for NowPlayingSource: Deezer, YouTube Music, browsers, any app that
// shows up in Control Center's player. Since macOS 15.4 MediaRemote only answers Apple-signed processes, so this
// library runs inside /usr/bin/perl: perl loads it, then calls overhead_now_playing_run, which never returns.
//
// Out (stdout), one JSON object per line, on every change:
//   {"bundle": "com.brave.Browser", "playing": true, "title": …, "artist": …, "album": …, "duration": 215.2,
//    "elapsed": 42.5, "timestamp": 1790000000.1, "artworkID": "…", "artwork": "<base64>"}
//   {"bundle": null} when nothing is playing anywhere.
//   "artwork" is only sent when it changed; "timestamp" (Unix time) is when "elapsed" was measured.
// In (stdin), one command per line: toggle, next, previous, seek <seconds>. End of input (Overhead quit): exit.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*ClientStringFn)(id);
typedef void (*IsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef Boolean (*SendCommandFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);

enum { kTogglePlayPause = 2, kNextTrack = 4, kPreviousTrack = 5 };  // MRMediaRemoteCommand

static RegisterFn registerForNotifications;
static GetInfoFn getInfo;
static GetClientFn getClient;
static ClientStringFn clientBundle, clientParentBundle;
static IsPlayingFn getIsPlaying;
static SendCommandFn sendCommand;
static SetElapsedFn setElapsed;

static dispatch_queue_t queue;  // serial: reads and writes never overlap
static NSString *lastArtworkID;
static NSString *lastLine;
static BOOL readPending;

static void emit(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return;
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([line isEqualToString:lastLine]) return;
    lastLine = line;
    fprintf(stdout, "%s\n", line.UTF8String);
    fflush(stdout);
}

static id orNull(id value) { return value ?: [NSNull null]; }

// Reads the client, its playing state and its info (three asynchronous calls, chained), then emits one line.
static void readState(void) {
    getClient(queue, ^(id client) {
        NSString *bundle = nil;
        if (client) {
            // A web page's player reports its browser as parent.
            bundle = clientParentBundle ? (__bridge NSString *)clientParentBundle(client) : nil;
            if (bundle.length == 0) bundle = (__bridge NSString *)clientBundle(client);
        }
        getIsPlaying(queue, ^(Boolean playing) {
            getInfo(queue, ^(CFDictionaryRef infoRef) {
                NSDictionary *info = (__bridge NSDictionary *)infoRef;
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if (bundle.length == 0 || title.length == 0) {
                    lastArtworkID = nil;
                    emit(@{@"bundle": [NSNull null]});
                    return;
                }
                NSMutableDictionary *out = [@{
                    @"bundle": bundle,
                    @"playing": playing ? @YES : @NO,
                    @"title": title,
                    @"artist": orNull(info[@"kMRMediaRemoteNowPlayingInfoArtist"]),
                    @"album": orNull(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]),
                    @"duration": orNull(info[@"kMRMediaRemoteNowPlayingInfoDuration"]),
                    @"elapsed": orNull(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]),
                } mutableCopy];
                NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if (timestamp) out[@"timestamp"] = @(timestamp.timeIntervalSince1970);
                NSString *artworkID = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"]
                    ?: [NSString stringWithFormat:@"%@|%@", title, out[@"artist"]];
                out[@"artworkID"] = artworkID;
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if (artwork.length > 0 && ![artworkID isEqualToString:lastArtworkID]) {
                    out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                    lastArtworkID = artworkID;
                }
                emit(out);
            });
        });
    });
}

// Notifications come in bursts: one read shortly after the first of a burst.
static void scheduleRead(void) {
    dispatch_async(queue, ^{
        if (readPending) return;
        readPending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), queue, ^{
            readPending = NO;
            readState();
        });
    });
}

static void runCommand(NSString *line) {
    if ([line isEqualToString:@"toggle"]) sendCommand(kTogglePlayPause, NULL);
    else if ([line isEqualToString:@"next"]) sendCommand(kNextTrack, NULL);
    else if ([line isEqualToString:@"previous"]) sendCommand(kPreviousTrack, NULL);
    else if ([line hasPrefix:@"seek "]) setElapsed([[line substringFromIndex:5] doubleValue]);
}

static void readCommands(void) {
    char buffer[256];
    while (fgets(buffer, sizeof buffer, stdin)) {
        NSString *line = [[NSString stringWithUTF8String:buffer]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length > 0) dispatch_async(queue, ^{ runCommand(line); });
    }
    exit(0);  // Overhead closed our input: it quit, or stopped reading other players
}

// Called by perl as an XSUB (its two arguments are perl's). Never returns.
__attribute__((visibility("default")))
void overhead_now_playing_run(void *perl, void *cv) {
    (void)perl; (void)cv;
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { fprintf(stderr, "MediaRemote not found\n"); exit(2); }
    registerForNotifications = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    getInfo = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getClient = dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");  // may be missing
    getIsPlaying = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    sendCommand = dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = dlsym(mr, "MRMediaRemoteSetElapsedTime");
    if (!registerForNotifications || !getInfo || !getClient || !clientBundle || !getIsPlaying || !sendCommand
        || !setElapsed) {
        fprintf(stderr, "MediaRemote functions missing\n");
        exit(3);
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    queue = dispatch_queue_create("com.overhead.nowplaying", DISPATCH_QUEUE_SERIAL);

    registerForNotifications(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { scheduleRead(); }];
    }
    scheduleRead();
    [NSThread detachNewThreadWithBlock:^{ readCommands(); }];
    CFRunLoopRun();
    exit(0);
}

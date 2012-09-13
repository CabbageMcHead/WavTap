#include <iostream>
#include <fstream>
#include <vector>
#include <Carbon/Carbon.h>
#include <AudioToolbox/AudioFile.h>
#include <AudioUnit/AudioUnit.h>
#include "AppController.h"
#include "AudioTee.h"

@implementation AppController

- (id)init {
  mTagForToggleRecord = 1;
  mTagForHistoryRecord = 2;
  mTagForQuit = 3;
  mIsRecording = NO;
  mDevices = new AudioDeviceList();
  mOutputDeviceID = 0;
  mWavTapDeviceID = 0;
  currentFrame = 0;
  totalFrames = 8;
  animTimer = NULL;
  mTimeSinceLaunch = 0;
  return self;
}

- (void)rebuildDeviceList{
  if (mDevices) mDevices->clear();
  UInt32 propsize;
  AudioObjectPropertyAddress theAddress = { kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
  AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &theAddress, 0, NULL,&propsize);
  int audioDeviceIDSize = sizeof(AudioDeviceID);
  int nDevices = propsize / audioDeviceIDSize;
  AudioDeviceID *devids = new AudioDeviceID[nDevices];
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &theAddress, 0, NULL, &propsize, devids);
  for (int i = 0; i < nDevices; ++i) {
    int mInputs = 2;
    AudioDevice dev(devids[i], mInputs);
    Device d;
    d.mID = devids[i];
    propsize = sizeof(d.mName);
    AudioObjectPropertyAddress addr = { kAudioDevicePropertyDeviceName, (dev.mIsInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput), 0 };
    AudioObjectGetPropertyData(dev.mID, &addr, 0, NULL,  &propsize, &d.mName);
    mDevices->push_back(d);
  }
  delete[] devids;
}

- (void)awakeFromNib {
  [[NSApplication sharedApplication] setDelegate:(id)self];
  [self rebuildDeviceList];
  for (AudioDeviceList::iterator i = mDevices->begin(); i != mDevices->end(); ++i) {
    if (0 == strcmp("WavTap", (*i).mName)) mWavTapDeviceID = (*i).mID;
  }
  [self initConnections];
  [self registerPropertyListeners];
  [self bindHotKeys];
  [self initStatusBar];
  [self buildMenu];
}

- (void)initStatusBar {
  mSbItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  NSImage *image = [NSImage imageNamed:@"menuIcon"];
  [image setTemplate:YES];
  [mSbItem setImage:image];
  NSImage *alternateImage = [NSImage imageNamed:@"menuIconInverse"];
  [alternateImage setTemplate:YES];
  [mSbItem setAlternateImage:alternateImage];
  [mSbItem setToolTip: @"WavTap"];
  [mSbItem setHighlightMode:YES];
}

- (void)onSecondPassed:(NSTimer*)timer {
  if(mTimeSinceLaunch++ < mEngine->mSecondsInHistoryBuffer){
    NSString *historyRecordMenuItemTitle = [NSString stringWithFormat:@"Save Last %d Secs", mTimeSinceLaunch];
    NSInteger tagKey = mTagForHistoryRecord;
    NSMenuItem *item = [mMenu itemWithTag:(NSInteger)tagKey];
    [item setTitle:historyRecordMenuItemTitle];
  } else {
    [timeElapsedTimer invalidate];
  }
}

- (void)buildMenu {
  NSMenuItem *item;
  mMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];
  if (mWavTapDeviceID){
    item = [mMenu addItemWithTitle:@"Start Recording" action:@selector(toggleRecord) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:(NSInteger)mTagForToggleRecord];
    [self setToggleRecordHotKey:@" "];
    NSString *historyRecordMenuItemTitle = @"Save Last 0 Secs";
    item = [mMenu addItemWithTitle:historyRecordMenuItemTitle action:@selector(historyRecord) keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:(NSInteger)mTagForHistoryRecord];
    timeElapsedTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onSecondPassed:) userInfo:nil repeats:YES];
  } else {
    item = [mMenu addItemWithTitle:@"Kernel Extension Not Installed" action:NULL keyEquivalent:@""];
    [item setTarget:self];
  }
  [mMenu addItem:[NSMenuItem separatorItem]];
  [mSbItem setMenu:mMenu];
  item = [mMenu addItemWithTitle:@"Quit" action:@selector(doQuit) keyEquivalent:@""];
  [item setTag:(NSInteger)mTagForQuit];
  [item setTarget:self];
  [mMenu setDelegate:(id)self];
}

OSStatus DeviceListenerProc (AudioObjectID inObjectID, UInt32 inNumberAddresses, const AudioObjectPropertyAddress inAddresses[], void*inClientData) {
  OSStatus err = noErr;
  AppController *app = (AppController *)CFBridgingRelease(inClientData);
  AudioObjectPropertyAddress addr;
  for(int i = 0; i < inNumberAddresses; i++){
    addr = inAddresses[i];
    switch(addr.mSelector) {
      case kAudioDevicePropertyAvailableNominalSampleRates:     { break; }
      case kAudioDevicePropertyClockDomain:                     { break; }
      case kAudioDevicePropertyConfigurationApplication:        { break; }
      case kAudioDevicePropertyDeviceCanBeDefaultDevice:        { break; }
      case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:  { break; }
      case kAudioDevicePropertyDeviceIsAlive:                   { break; }
      case kAudioDevicePropertyDeviceIsRunning:                 { break; }
      case kAudioDevicePropertyDeviceUID:                       { break; }
      case kAudioDevicePropertyIcon:                            { break; }
      case kAudioDevicePropertyIsHidden:                        { break; }
      case kAudioDevicePropertyLatency:                         { break; }
      case kAudioDevicePropertyModelUID:                        { break; }
      case kAudioDevicePropertyNominalSampleRate:{
        app->mEngine->Stop();
        printf("(DeviceListenerProc) MatchSampleRates returned status code: %u \n", err);
        app->mEngine->Start();
        break;
      }
      case kAudioDevicePropertyPreferredChannelLayout:          { break; }
      case kAudioDevicePropertyPreferredChannelsForStereo:      { break; }
      case kAudioDevicePropertyRelatedDevices:                  { break; }
      case kAudioDevicePropertySafetyOffset:                    { break; }
      case kAudioDevicePropertyStreams:                         { break; }
      case kAudioDevicePropertyTransportType:                   { break; }
      case kAudioObjectPropertyControlList:                     { break; }
      case kAudioDeviceProcessorOverload:{
        printf("kAudioDeviceProcessorOverload detected!");
        break;
      }
    }
  }
  return err;
}

- (void)registerPropertyListeners {
  AudioObjectPropertyAddress addr = { kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
  AudioObjectAddPropertyListener(mEngine->mOutputDevice.mID, &addr, DeviceListenerProc, (__bridge void *)self);
  addr.mElement = kAudioDeviceProcessorOverload;
  addr.mScope = kAudioObjectPropertyScopeWildcard;
  AudioObjectAddPropertyListener(mEngine->mInputDevice.mID, &addr, DeviceListenerProc, (__bridge void *)self);
  AudioObjectAddPropertyListener(mEngine->mOutputDevice.mID, &addr, DeviceListenerProc, (__bridge void *)self);
}

- (void)setToggleRecordHotKey:(NSString*)keyEquivalent {
  NSMenuItem *item = [mMenu itemWithTag:mTagForToggleRecord];
  [item setKeyEquivalentModifierMask: NSControlKeyMask | NSCommandKeyMask];
  [item setKeyEquivalent:keyEquivalent];
}

- (void)initConnections {
  Float32 maxVolume = 1.0;
  UInt32 size = sizeof(AudioDeviceID);
  AudioObjectPropertyAddress devCurrDefAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &devCurrDefAddress, 0, NULL, &size, &mStashedAudioDeviceID);
  mOutputDeviceID = mStashedAudioDeviceID;
  AudioObjectPropertyAddress volCurrDef1Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 1 };
  size = sizeof(Float32);
  AudioObjectGetPropertyData(mStashedAudioDeviceID, &volCurrDef1Address, 0, NULL, &size, &mStashedVolume);
  AudioObjectPropertyAddress volCurrDef2Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 2 };
  size = sizeof(Float32);
  AudioObjectGetPropertyData(mStashedAudioDeviceID, &volCurrDef2Address, 0, NULL, &size, &mStashedVolume2);
  mEngine = new AudioTee(mWavTapDeviceID, mOutputDeviceID);
  AudioObjectPropertyAddress volSwapWav0Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 0 };
  AudioObjectSetPropertyData(mWavTapDeviceID, &volSwapWav0Address, 0, NULL, sizeof(Float32), &maxVolume);
  AudioObjectPropertyAddress volSwapWav1Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 1 };
  AudioObjectSetPropertyData(mWavTapDeviceID, &volSwapWav1Address, 0, NULL, sizeof(Float32), &maxVolume);
  AudioObjectPropertyAddress volSwapWav2Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 2 };
  AudioObjectSetPropertyData(mWavTapDeviceID, &volSwapWav2Address, 0, NULL, sizeof(Float32), &maxVolume);
  mEngine->Start();
  AudioObjectSetPropertyData(kAudioObjectSystemObject, &devCurrDefAddress, 0, NULL, sizeof(AudioDeviceID), &mWavTapDeviceID);
}

- (OSStatus)restoreSystemOutputDevice {
  OSStatus err = noErr;
  AudioObjectPropertyAddress devAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
  err = AudioObjectSetPropertyData(kAudioObjectSystemObject, &devAddress, 0, NULL, sizeof(AudioDeviceID), &mStashedAudioDeviceID);
  return err;
}

- (OSStatus)restoreSystemOutputDeviceVolume {
  OSStatus err = noErr;
  AudioObjectPropertyAddress volAddress = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 1 };
  AudioObjectSetPropertyData(kAudioObjectSystemObject, &volAddress, 0, NULL, sizeof(Float32), &mStashedVolume);
  AudioObjectPropertyAddress vol2Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 2 };
  err = AudioObjectSetPropertyData(kAudioObjectSystemObject, &vol2Address, 0, NULL, sizeof(Float32), &mStashedVolume2);
  return err;
}

OSStatus recordHotKeyHandler(EventHandlerCallRef nextHandler, EventRef anEvent, void *userData) {
  AppController* inUserData = (__bridge AppController*)userData;
  [inUserData toggleRecord];
  return noErr;
}

OSStatus historyRecordHotKeyHandler(EventHandlerCallRef nextHandler, EventRef anEvent, void *userData) {
  AppController* inUserData = (__bridge AppController*)userData;
  [inUserData historyRecord];
  return noErr;
}

- (void)bindHotKeys {
  recordHotKeyFunction = NewEventHandlerUPP(recordHotKeyHandler);
  EventTypeSpec eventType0;
  eventType0.eventClass = kEventClassKeyboard;
  eventType0.eventKind = kEventHotKeyReleased;
  InstallApplicationEventHandler(recordHotKeyFunction, 1, &eventType0, (void *)CFBridgingRetain(self), NULL);
  EventHotKeyRef theRef0;
  EventHotKeyID keyID0;
  keyID0.signature = 'a';
  keyID0.id = 0;
  RegisterEventHotKey(49, cmdKey+controlKey, keyID0, GetApplicationEventTarget(), 0, &theRef0);
}

-(void)launchRecordProcess {
  NSString *sharedSupportPath = [[NSBundle bundleForClass:AppController.class] sharedSupportPath];
  NSString *scriptName = @"record";
  NSString *scriptExtension = @"sh";
  NSString *scriptAbsPath = [NSString stringWithFormat:@"%@/%@.%@", sharedSupportPath, scriptName, scriptExtension];
  NSString *bits = [NSString stringWithFormat:@"%d", mEngine->mOutputDevice.getStreamPhysicalBitDepth(false)];
  NSTask *task=[[NSTask alloc] init];
  NSArray *argv=[NSArray arrayWithObject:bits];
  [task setArguments: argv];
  [task setLaunchPath:scriptAbsPath];
  [task launch];
}

-(void)killRecordProcesses {
  NSString *sharedSupportPath = [[NSBundle bundleForClass:AppController.class] sharedSupportPath];
  NSString *scriptName = @"kill_recorders";
  NSString *scriptExtension = @"sh";
  NSString *scriptAbsolutePath = [NSString stringWithFormat:@"%@/%@.%@", sharedSupportPath, scriptName, scriptExtension];
  NSTask *task=[[NSTask alloc] init];
  NSArray *argv=[NSArray arrayWithObjects:nil];
  [task setArguments: argv];
  [task setLaunchPath:scriptAbsolutePath];
  [task launch];
}

- (void)startAnimatingStatusBarIcon {
  animTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/16.0 target:self selector:@selector(updateStatusBarIcon:) userInfo:nil repeats:YES];
}

- (void)stopAnimatingStatusBarIcon {
  [animTimer invalidate];
}

- (void)updateStatusBarIcon:(NSTimer*)timer {
  NSImage* image = [NSImage imageNamed:[NSString stringWithFormat:@"menuIcon%d", (currentFrame++ % totalFrames)]];
  [image setTemplate:YES];
  [mSbItem setImage:image];
}

-(void)recordStart {
  NSMenuItem *item = [mMenu itemWithTag:mTagForToggleRecord];
  [self launchRecordProcess];
  [item setTitle:@"Stop Recording"];
  [self startAnimatingStatusBarIcon];
  mIsRecording = YES;
}

-(void)recordStop {
  NSMenuItem *item = [mMenu itemWithTag:mTagForToggleRecord];
  [self killRecordProcesses];
  [self stopAnimatingStatusBarIcon];
  [item setTitle:@"Start Recording"];
  mIsRecording = NO;
}

-(void)toggleRecord {
  (mIsRecording) ? [self recordStop] : [self recordStart];
}

-(void)historyRecord {
  NSString *destDirname = [NSString stringWithFormat:@"%@", [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0]];
  NSDate *date = [NSDate date];
  long time1 = (long) [date timeIntervalSince1970];
  long time0 = (long) time1 - mEngine->mSecondsInHistoryBuffer;
  NSString *fileName = [NSString stringWithFormat:@"%@-%@", [NSString stringWithFormat:@"%ld", time0], [NSString stringWithFormat:@"%ld", time1]];
  NSString *fileExt = @"wav";
  NSString *relativeFilePath = [NSString stringWithFormat:@"%@.%@", fileName, fileExt];
  NSString *absoluteFilePath = [NSString stringWithFormat:@"%@/%@", destDirname, relativeFilePath];
  mEngine->saveHistoryBuffer([absoluteFilePath UTF8String], mEngine->mSecondsInHistoryBuffer);
}

- (void)cleanupOnBeforeQuit {
  if(mIsRecording) [self recordStop];
  if(mEngine) mEngine->Stop();
  [self restoreSystemOutputDevice];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  [self cleanupOnBeforeQuit];
}

- (void)doQuit {
  [self cleanupOnBeforeQuit];
  [NSApp terminate:nil];
}

@end
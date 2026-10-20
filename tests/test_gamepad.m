// Exercise the real Apple snapshot profile through the adapter and guest HID return.
#import <Foundation/Foundation.h>
#include "../third_party/nxnative/dm/host/hle.h"
#undef HLE_FORCE
#define HLE_FORCE(symbol, reason, result, name, ...) static result name(__VA_ARGS__)
#include "../third_party/nxnative/dm/host/hle_hid.c"
#include "../native/gamepad_mac.m"
#include <assert.h>
uint64_t dm_guest_frame(void) { return 0; }
int dm_opmode(void) { return 1; }
uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000000000ull + t.tv_nsec; }
static NpadState sample(void) { NpadState s; fill(&s, 0, STYLE_FULLKEY); return s; }
static void drain(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; }
int main(void) { @autoreleasepool {
    unsetenv("DM_PAD_FACE"); unsetenv("DM_PAD_DEADZONE");
    setenv("DM_HID_RECEIPT_LOG", "work/test-controller.jsonl", 1);
    NSArray *hardware = GCController.controllers;
    fprintf(stderr, "Physical controllers visible: %lu\n", (unsigned long)hardware.count);
    for (GCController *c in hardware) fprintf(stderr, "Physical: %s (%s)\n", c.vendorName.UTF8String, c.productCategory.UTF8String);
    dm_gamepad_start(NULL);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    hardware = GCController.controllers;
    for (GCController *c in hardware) { fprintf(stderr, "Discovered physical: %s (%s)\n", c.vendorName.UTF8String, c.productCategory.UTF8String); detach(c); }
    GCController *c = [GCController controllerWithExtendedGamepad];
    GCController *second = [GCController controllerWithExtendedGamepad];
    [[NSNotificationCenter defaultCenter] postNotificationName:GCControllerDidConnectNotification object:c]; drain();
    assert(dm_gamepad_count() == 1);
    GCExtendedGamepad *g = c.extendedGamepad;
    // Default is the Eden profile: Circle (GC buttonB) is the Switch B button.
    [g.buttonB setValue:1]; publish(c,g); assert(sample().buttons & DM_BTN_B);
    [g.buttonB setValue:0]; publish(c,g); assert(sample().buttons == 0);
    g_face_letter = 0;   // DM_PAD_FACE=position restores the Switch physical layout
    [g.buttonB setValue:1]; publish(c,g); assert(sample().buttons & DM_BTN_A);
    [g.buttonB setValue:0]; publish(c,g); assert(sample().buttons == 0); g_face_letter = 1;
    [g.buttonA setValue:1]; [g.buttonY setValue:1]; [g.buttonX setValue:1];
    [g.leftShoulder setValue:1]; publish(c,g); assert(sample().buttons == (DM_BTN_A|DM_BTN_X|DM_BTN_Y|DM_BTN_R));   // R1 = Switch R
    [g.leftShoulder setValue:0]; [g.rightShoulder setValue:1]; publish(c,g); assert(sample().buttons == (DM_BTN_A|DM_BTN_X|DM_BTN_Y|DM_BTN_L));   // L1 = Switch L
    [g.leftShoulder setValue:1];
    [g.leftTrigger setValue:1]; [g.rightTrigger setValue:1];
    [g.leftThumbstickButton setValue:1]; [g.rightThumbstickButton setValue:1];
    [g.buttonMenu setValue:1]; [g.buttonOptions setValue:1];
    [g.dpad setValueForXAxis:-1 yAxis:1]; publish(c,g);
    uint64_t expected = DM_BTN_A|DM_BTN_X|DM_BTN_Y|DM_BTN_L|DM_BTN_R|DM_BTN_ZL|DM_BTN_ZR|DM_BTN_LS|DM_BTN_RS|DM_BTN_PLUS|DM_BTN_MINUS|DM_BTN_LEFT|DM_BTN_UP;
    assert(sample().buttons == expected);
    [g.leftThumbstick setValueForXAxis:0.05 yAxis:0.04];
    [g.rightThumbstick setValueForXAxis:1 yAxis:-1]; publish(c,g);
    NpadState s = sample(); assert(s.lx == 0 && s.ly == 0); assert(s.rx > 23000 && s.ry < -23000);
    dm_gamepad_set_active(0); assert(sample().buttons == 0 && sample().rx == 0);
    publish(c,g); assert(sample().buttons == 0); // Background events cannot restore input.
    dm_gamepad_set_active(1);
    // Snapshots are not in the physical inventory, so explicitly poll this test device.
    publish(c,g); assert(sample().buttons & DM_BTN_PLUS);
    detach(c); assert(sample().buttons == 0);
    attach(c); attach(second); assert(dm_gamepad_count() == 2);
    [second.extendedGamepad.buttonB setValue:1]; publish(second, second.extendedGamepad);
    detach(c); assert(sample().buttons & DM_BTN_A); // Other controller survives unplug.
    [[NSNotificationCenter defaultCenter] postNotificationName:GCControllerDidDisconnectNotification object:second]; drain();
    assert(dm_gamepad_count() == 0 && sample().buttons == 0);
    // Clear an unconsumed press on focus loss, including the HID edge latch.
    attach(c); publish(c,g); dm_gamepad_set_active(0); assert(sample().buttons == 0);
    int32_t x,y; stick(NAN,0,&x,&y); assert(x == 0 && y == 0);
    g_face_letter = 1; dm_gamepad_set_active(1); publish(c,g); assert(sample().buttons & DM_BTN_A);
    fprintf(stderr, "PASS: mapping, axes, focus, edge clearing, hot plug, multiple controllers, HID receipt\n");
} return 0; }

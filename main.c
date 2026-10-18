/*  setleds for Mac
    https://github.com/damieng/setledsmac
    Copyright 2015-2025 Damien Guard. GPL 2 licenced.

    Modified: added -d / --daemon mode so the physical NumLock key toggles the
    numeric keypad. macOS has no NumLock state machine: pressing NumLock
    (HID usage 0x53, "Clear") never makes the host send the NumLock LED output
    report back to the keyboard, so the firmware never switches the keypad.
    The daemon watches for the key at the HID level and re-uses the exact same
    LED-writing code path as the one-shot `setleds ^num` command, which is
    proven to switch the keypad on this hardware.

    Note for laptops with an ITE embedded controller (e.g. Lenovo Legion):
    the built-in keyboard exposes a vendor-defined top-level collection, so a
    Keyboard-usage device match does NOT see it - yet it is the device that
    actually delivers the NumLock key events. The daemon therefore matches
    ALL HID devices for listening, while LED writes still only go through the
    regular keyboard devices (identical to plain `setleds +num`).
 */

#include "main.h"
#include <fnmatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <strings.h>
#include <time.h>
#include <IOKit/hid/IOHIDLib.h>

bool verbose = false;
const char * nameMatch;
static bool daemonMode = false;

int main(int argc, const char * argv[])
{
    printf("SetLEDs version 0.5 - https://github.com/damieng/setledsmac\n");
    parseOptions(argc, argv);
    printf("\n");
    return 0;
}

void parseOptions(int argc, const char * argv[])
{
    if (argc == 1) {
        explainUsage();
        exit(1);
    }

    LedState changes[] = { NoChange, NoChange, NoChange, NoChange, NoChange, NoChange };

    bool nextIsName = false;

    for (int i = 1; i < argc; i++) {
        if (strcasecmp(argv[i], "-v") == 0)
            verbose = true;
        else if(strcasecmp(argv[i], "-name") == 0)
            nextIsName = true;
        else if (strcasecmp(argv[i], "-d") == 0 || strcasecmp(argv[i], "--daemon") == 0)
            daemonMode = true;

        // Numeric lock
        else if (strcasecmp(argv[i], "+num") == 0)
            changes[kHIDUsage_LED_NumLock] = On;
        else if (strcasecmp(argv[i], "-num") == 0)
            changes[kHIDUsage_LED_NumLock] = Off;
        else if (strcasecmp(argv[i], "^num") == 0)
            changes[kHIDUsage_LED_NumLock] = Toggle;

        // Caps lock
        else if (strcasecmp(argv[i], "+caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = On;
        else if (strcasecmp(argv[i], "-caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = Off;
        else if (strcasecmp(argv[i], "^caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = Toggle;

        // Scroll lock
        else if (strcasecmp(argv[i], "+scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = On;
        else if (strcasecmp(argv[i], "-scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = Off;
        else if (strcasecmp(argv[i], "^scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = Toggle;

        // Compose
        else if (strcasecmp(argv[i], "+compose") == 0)
            changes[kHIDUsage_LED_Compose] = On;
        else if (strcasecmp(argv[i], "-compose") == 0)
            changes[kHIDUsage_LED_Compose] = Off;
        else if (strcasecmp(argv[i], "^compose") == 0)
            changes[kHIDUsage_LED_Compose] = Toggle;

        // Kana
        else if (strcasecmp(argv[i], "+kana") == 0)
            changes[kHIDUsage_LED_Kana] = On;
        else if (strcasecmp(argv[i], "-kana") == 0)
            changes[kHIDUsage_LED_Kana] = Off;
        else if (strcasecmp(argv[i], "^kana") == 0)
            changes[kHIDUsage_LED_Kana] = Toggle;

        else {
            if (nextIsName) {
                nameMatch = argv[i];
                nextIsName = false;
            }
            else {
                fprintf(stderr, "Unknown option %s\n\n", argv[i]);
                explainUsage();
                exit(1);
            }
        }
    }

    if (daemonMode) {
        /* In daemon mode any +/-/^ options only set the initial state; the
         * daemon then keeps running and toggles NumLock on every keypress. */
        bool anyChange = false;
        for (int i = 0; i <= maxLeds; i++)
            if (changes[i] != NoChange) anyChange = true;
        if (anyChange)
            setAllKeyboards(changes);

        int initialNum = -1; /* -1 = leave as-is */
        if (changes[kHIDUsage_LED_NumLock] == On) initialNum = 1;
        else if (changes[kHIDUsage_LED_NumLock] == Off) initialNum = 0;
        runNumLockDaemon(initialNum);
    }
    else {
        setAllKeyboards(changes);
    }
}

void explainUsage(void)
{
    printf("Usage:\tsetleds [-v] [-name wildcard] [[+|-|^][ num | caps | scroll | compose | kana ]]\n"
           "\tsetleds -d / --daemon [ +num | -num ]   run as a daemon: the NumLock key toggles the keypad\n"
           "\t                                        (-d 启动NumLock按键监听守护模式，按NumLock切换小键盘)\n"
           "Thus,\tsetleds +caps -num ^scroll\n"
           "will set CapsLock, clear NumLock and toggle ScrollLock.\n"
           "Any leds changed are reported for each keyboard.\n"
           "Specify -v to shows state of all leds.\n"
           "Specify -name to match keyboard name with a wildcard\n"
           "Specify -d to keep running and toggle NumLock when the NumLock key is pressed\n");
}

Boolean isKeyboardDevice(IOHIDDeviceRef device)
{
    return IOHIDDeviceConformsTo(device, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard);
}

void setKeyboard(IOHIDDeviceRef device, CFDictionaryRef keyboardDictionary, LedState changes[])
{
    CFStringRef deviceNameRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (!deviceNameRef) return;

    const char * deviceName = CFStringGetCStringPtr(deviceNameRef, kCFStringEncodingUTF8);

    if (nameMatch && fnmatch(nameMatch, deviceName, 0) != 0)
        return;

    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, keyboardDictionary, kIOHIDOptionsTypeNone);
    bool missingState = false;

    if (elements) {
        long elementCount = CFArrayGetCount(elements);
        bool printedName = false;
        for (CFIndex elementIndex = 0; elementIndex < elementCount; elementIndex++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, elementIndex);

            if (element && kHIDPage_LEDs == IOHIDElementGetUsagePage(element)) {
                uint32_t led = IOHIDElementGetUsage(element);

                if (led > maxLeds) break;

                if (!printedName) {
                    printf("\n \"%s\" ", deviceName);
                    printedName = true;
                }

                // Get current keyboard led status
                IOHIDValueRef currentValue = 0;
                IOHIDDeviceGetValue(device, element, &currentValue);

                if (currentValue == 0x00) {
                    missingState = true;
                    printf("?%s ", ledNames[led - 1]);
                } else {
                    long current = IOHIDValueGetIntegerValue(currentValue);
                    CFRelease(currentValue);

                    // Should we try to set the led?
                    if (changes[led] != NoChange && changes[led] != current) {
                        LedState newState = changes[led];
                        if (newState == Toggle) {
                            newState = current == 0 ? On : Off;
                        }
                        IOHIDValueRef newValue = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, newState);
                        if (newValue) {
                            IOReturn changeResult = IOHIDDeviceSetValue(device, element, newValue);

                            // Was the change successful?
                            if (kIOReturnSuccess == changeResult) {
                                printf("%s%s ", stateSymbol[newState], ledNames[led - 1]);
                            }
                            CFRelease(newValue);
                        }
                    } else if (verbose) {
                        printf("%s%s ", stateSymbol[current], ledNames[led - 1]);
                    }
                }
            }
        }
        CFRelease(elements);
    }

    printf("\n");
    if (missingState) {
        printf("\nSome state could not be determined. Please try running as root/sudo.\n");
    }
}

void setAllKeyboards(LedState changes[])
{
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        fprintf(stderr, "Failed to create IOHID manager.\n");
        return;
    }

    CFDictionaryRef keyboard = getKeyboardDictionary();
    if (!keyboard) {
        fprintf(stderr, "Failed to get dictionary usage page for kHIDUsage_GD_Keyboard.\n");
        return;
    }

    IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(manager, keyboard);

    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    if (devices) {
        CFIndex deviceCount = CFSetGetCount(devices);
        if (deviceCount == 0) {
            fprintf(stderr, "Could not find any keyboard devices.\n");
        }
        else {
            // Loop through all keyboards attempting to get or display led state
            IOHIDDeviceRef *deviceRefs = malloc(sizeof(IOHIDDeviceRef) * deviceCount);
            if (deviceRefs) {
                CFSetGetValues(devices, (const void **) deviceRefs);
                for (CFIndex deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++)
                    if (isKeyboardDevice(deviceRefs[deviceIndex]))
                        setKeyboard(deviceRefs[deviceIndex], keyboard, changes);

                free(deviceRefs);
            }
        }

        CFRelease(devices);
    }

    CFRelease(keyboard);
}

CFMutableDictionaryRef getKeyboardDictionary(void)
{
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    if (!result) return result;

    UInt32 inUsagePage = kHIDPage_GenericDesktop;
    UInt32 inUsage = kHIDUsage_GD_Keyboard;

    CFNumberRef page = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &inUsagePage);
    if (page) {
        CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsagePageKey), page);
        CFRelease(page);

        CFNumberRef usage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &inUsage);
        if (usage) {
            CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsageKey), usage);
            CFRelease(usage);
        }
    }
    return result;
}

/* ------------------------------------------------------------------ */
/*  NumLock daemon mode                                                */
/* ------------------------------------------------------------------ */

static double lastToggleTime = 0.0;
static int forcedNumState = -1; /* -1 = leave LEDs alone, 0/1 = force when a keyboard appears */

static double nowSec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1.0e9;
}

static void copyDeviceName(IOHIDDeviceRef device, char *out, size_t n)
{
    out[0] = 0;
    CFStringRef r = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (r) CFStringGetCString(r, out, (CFIndex)n, kCFStringEncodingUTF8);
}

/* Apply an explicit NumLock state to one (possibly just-arrived) keyboard.
 * Only real keyboard devices are touched - the same devices `setleds +num`
 * writes to - so we never poke the ITE vendor interface. */
static void applyNumLockToDevice(IOHIDDeviceRef device, int on)
{
    if (!isKeyboardDevice(device)) return;

    CFDictionaryRef keyboard = getKeyboardDictionary();
    if (!keyboard) return;

    LedState changes[] = { NoChange, NoChange, NoChange, NoChange, NoChange, NoChange };
    changes[kHIDUsage_LED_NumLock] = on ? On : Off;
    setKeyboard(device, keyboard, changes);
    CFRelease(keyboard);
}

/* Fires for every HID device present at start and for any that appear later
 * (e.g. the keyboard finishing enumeration after the daemon launched). */
static void daemonDeviceAdded(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef device)
{
    if (forcedNumState >= 0)
        applyNumLockToDevice(device, forcedNumState);
}

/* Manager-wide input callback: fires for HID events from every device the
 * manager opened. We only care about NumLock key-down (usage page 0x07,
 * usage 0x53, value != 0). */
static void daemonInputCallback(void *ctx, IOReturn result, void *sender, IOHIDValueRef value)
{
    IOHIDElementRef element = IOHIDValueGetElement(value);
    if (!element) return;
    if (IOHIDElementGetUsagePage(element) != kHIDPage_KeyboardOrKeypad) return;
    if (IOHIDElementGetUsage(element) != kHIDUsage_KeypadNumLock) return;
    if (IOHIDValueGetIntegerValue(value) == 0) return; /* key-up */

    /* Debounce: one press can be reported by more than one interface */
    double t = nowSec();
    if (t - lastToggleTime < 0.25) return;
    lastToggleTime = t;

    char name[128] = "?";
    copyDeviceName((IOHIDDeviceRef)sender, name, sizeof(name));
    printf("NumLock key from '%s' -> toggling keypad\n", name);

    /* Re-use the exact `setleds ^num` code path: read current LED state on
     * each keyboard and flip it. */
    LedState changes[] = { NoChange, NoChange, NoChange, NoChange, NoChange, NoChange };
    changes[kHIDUsage_LED_NumLock] = Toggle;
    setAllKeyboards(changes);
}

void runNumLockDaemon(int initialNumState)
{
    forcedNumState = initialNumState;

    /* Log unbuffered so launchd's StandardOutPath gets every line at once */
    setvbuf(stdout, NULL, _IONBF, 0);

    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        fprintf(stderr, "Failed to create IOHID manager.\n");
        exit(1);
    }

    /* Match EVERY HID device: the built-in keyboard's top-level collection is
     * vendor-defined (ITE EC) and a Keyboard-usage match would never see the
     * NumLock key events it emits. LED writes are unaffected - they go through
     * setAllKeyboards()/setKeyboard() which match real keyboards only. */
    IOHIDManagerSetDeviceMatching(manager, NULL);

    IOHIDManagerRegisterDeviceMatchingCallback(manager, daemonDeviceAdded, NULL);
    IOHIDManagerRegisterInputValueCallback(manager, daemonInputCallback, NULL);
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

    IOReturn openResult = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    if (openResult != kIOReturnSuccess) {
        fprintf(stderr, "Could not open HID devices: 0x%x\n"
                "Run with sudo (or grant this binary Input Monitoring in System Settings).\n",
                openResult);
        exit(1);
    }

    /* Let the device-matching callbacks run once so initial/late-arriving
     * keyboards get the forced state before we settle into the run loop. */
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);

    printf("setleds daemon running%s - press NumLock to toggle (Ctrl-C to stop)\n",
           forcedNumState >= 0 ? (forcedNumState ? " (initial NumLock ON)" : " (initial NumLock OFF)") : "");

    CFRunLoopRun();
}

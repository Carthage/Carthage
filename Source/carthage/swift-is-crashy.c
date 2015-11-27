//
//  swift-is-crashy.c
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-05-25.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

#include <errno.h>
#include <execinfo.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char * const exceptionPrelude = "\n"
	"Caught signal triggered by the Swift runtime!\n";

static const char * const exceptionExplanation = "\n"
	"\n"
	"Unfortunately, this is probably a bug in Swift and not Carthage. If\n"
	"this is preventing you from doing work, please file an issue and we'll\n"
	"do our best to work around it:\n"
	"\033[4mhttps://github.com/Carthage/Carthage/issues/new\033[0m\n"
	"\n"
	"Please also consider filing a radar with Apple, containing the version\n"
	"of Carthage and any crash report found in Console.app.\n"
	"\n";

// strnlen isn't on the async-signal safe list, but the implementation is 
// pretty much the same as this. If this is overkill, just replace with 
// the standard strnlen.
static size_t safe_strnlen(const char * string, size_t max) {
	for (size_t i = 0; i < max; ++i) {
		if (string[i] == '\0') {
			return i;
		}
	}

	return max;
}

static void uncaughtSignal(int zig, siginfo_t *info, void *context) {
	size_t preludeLength = safe_strnlen(exceptionPrelude, 90); // 47 at this time
	size_t explanationLength = safe_strnlen(exceptionExplanation, 900); // 356 at this time
	const char *signalName = zig < NSIG ? sys_siglist[zig] : "Unknown signal";
	size_t signalNameLength = safe_strnlen(signalName, 90); // Currently they are all less than 25
	
	write(STDERR_FILENO, exceptionPrelude, preludeLength);
	write(STDERR_FILENO, signalName, signalNameLength);
	write(STDERR_FILENO, exceptionExplanation, explanationLength);
	
	raise(zig); // for great justice
}

static void setUpSignalHandlers(void) __attribute__((constructor)) {
	struct sigaction action = {
		.sa_sigaction = &uncaughtSignal,
		.sa_flags = SA_NODEFER | SA_RESETHAND | SA_SIGINFO,
	};

	sigemptyset(&action.sa_mask);

	sigaction(SIGILL, &action, NULL);
	sigaction(SIGBUS, &action, NULL);
	sigaction(SIGSEGV, &action, NULL);
}

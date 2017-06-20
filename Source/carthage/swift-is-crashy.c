#include <errno.h>
#include <execinfo.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char exceptionPrelude[] = "\n"
	"Caught signal triggered by the Swift runtime!\n";

static const char exceptionExplanation[] = "\n"
	"\n"
	"Unfortunately, this is probably a bug in Swift and not Carthage. If\n"
	"this is preventing you from doing work, please file an issue and we'll\n"
	"do our best to work around it:\n"
	"\033[4mhttps://github.com/Carthage/Carthage/issues/new\033[0m\n"
	"\n"
	"Please also consider filing a radar with Apple, containing the version\n"
	"of Carthage and any crash report found in Console.app.\n"
	"\n";

static void uncaughtSignal(int zig, siginfo_t *info, void *context) {
	const size_t preludeLength = sizeof exceptionPrelude;
	const size_t explanationLength = sizeof exceptionExplanation;
	const char *signalName = zig < NSIG ? sys_siglist[zig] : "Unknown signal";
	const size_t signalNameLength = strlen(signalName);
	
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

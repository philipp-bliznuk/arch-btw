// qs-gpu-busy [interval_s] — i915 engine busy % via the i915 PMU (same source
// btop / intel_gpu_top use). Needs CAP_PERFMON; post-install.sh installs it
// root-owned to /usr/local/bin with the capability set.
// Prints "<render%> <video%>" per interval; quickshell/core/Metrics.qml reads it.
#define _GNU_SOURCE
#include <fcntl.h>
#include <linux/perf_event.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static int pmu_type(void) {
	FILE *f = fopen("/sys/bus/event_source/devices/i915/type", "r");
	if (!f)
		return -1;
	int t = -1;
	if (fscanf(f, "%d", &t) != 1)
		t = -1;
	fclose(f);
	return t;
}

static long long event_config(const char *name) {
	char path[256];
	snprintf(path, sizeof path, "/sys/bus/event_source/devices/i915/events/%s", name);
	FILE *f = fopen(path, "r");
	if (!f)
		return -1;
	unsigned long long c = 0;
	int ok = fscanf(f, "config=0x%llx", &c) == 1;
	fclose(f);
	return ok ? (long long)c : -1;
}

static uint64_t read_u64(int fd) {
	uint64_t v = 0;
	if (read(fd, &v, sizeof v) != (ssize_t)sizeof v)
		return 0;
	return v;
}

static uint64_t now_ns(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static int open_engine(int type, const char *event) {
	long long config = event_config(event);
	if (config < 0)
		return -1;
	struct perf_event_attr attr;
	memset(&attr, 0, sizeof attr);
	attr.type = (uint32_t)type;
	attr.size = sizeof attr;
	attr.config = (uint64_t)config;
	return (int)syscall(__NR_perf_event_open, &attr, -1, 0, -1, 0);
}

static int pct(uint64_t delta, double dt) {
	int busy = dt > 0 ? (int)(100.0 * (double)delta / dt + 0.5) : 0;
	return busy > 100 ? 100 : busy;
}

int main(int argc, char **argv) {
	unsigned interval = argc > 1 ? (unsigned)atoi(argv[1]) : 2;
	if (interval < 1)
		interval = 1;
	int type = pmu_type();
	if (type < 0) {
		fprintf(stderr, "qs-gpu-busy: i915 PMU not available\n");
		return 1;
	}
	int render = open_engine(type, "rcs0-busy");
	if (render < 0) {
		perror("qs-gpu-busy: perf_event_open (needs CAP_PERFMON)");
		return 1;
	}
	int video = open_engine(type, "vcs0-busy");
	setvbuf(stdout, NULL, _IOLBF, 0);
	uint64_t pr = read_u64(render), pv = video >= 0 ? read_u64(video) : 0, pt = now_ns();
	for (;;) {
		sleep(interval);
		uint64_t r = read_u64(render), v = video >= 0 ? read_u64(video) : 0, t = now_ns();
		double dt = (double)(t - pt);
		printf("%d %d\n", pct(r - pr, dt), pct(v - pv, dt));
		pr = r;
		pv = v;
		pt = t;
	}
}

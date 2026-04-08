/*
 * stp-toggle.c
 * Monitors the touchpad LED button area for double-taps and toggles the Synaptics LED.
 * Only grabs (blocks) the touchpad when the LED is ON.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <linux/input.h>
#include <sys/select.h>
#include <glob.h>
#include <sys/ioctl.h>

#define LED_PATH "/sys/class/leds/psmouse::synaptics/brightness"
#define DOUBLE_TAP_WINDOW_MS 500

/* LED button zone coordinates (adjust based on your device) */
#define LED_ZONE_X_MIN 1000
#define LED_ZONE_X_MAX 1500
#define LED_ZONE_Y_MIN 1000
#define LED_ZONE_Y_MAX 1500

static int read_led_state(void)
{
	FILE *f;
	int state = 0;

	f = fopen(LED_PATH, "r");
	if (!f)
		return -1;

	if (fscanf(f, "%d", &state) != 1)
		state = -1;

	fclose(f);
	return state;
}

static int toggle_led(void)
{
	int current = read_led_state();
	if (current < 0) {
		perror("Failed to read LED state");
		return -1;
	}

	int new_state = 1 - current;

	FILE *f = fopen(LED_PATH, "w");
	if (!f) {
		perror("Failed to open LED brightness for writing");
		return -1;
	}

	fprintf(f, "%d", new_state);
	fclose(f);

	fprintf(stderr, "LED toggled: %s\n", new_state ? "ON" : "OFF");
	return new_state;
}

static int find_touchpad(char *path, size_t path_len)
{
	glob_t gl;
	int i;

	if (glob("/dev/input/event*", 0, NULL, &gl) != 0)
		return -1;

	for (i = 0; i < gl.gl_pathc; i++) {
		int fd;
		char name[256];

		fd = open(gl.gl_pathv[i], O_RDONLY);
		if (fd < 0)
			continue;

		if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0) {
			close(fd);
			continue;
		}

		/* Look for Synaptics/Touchpad, skip pass-through */
		if ((strstr(name, "Synaptics") || strstr(name, "Touchpad")) &&
		    !strstr(name, "Pass")) {
			snprintf(path, path_len, "%s", gl.gl_pathv[i]);
			fprintf(stderr, "Found touchpad: %s (%s)\n", name, path);
			close(fd);
			globfree(&gl);
			return 0;
		}

		close(fd);
	}

	globfree(&gl);
	return -1;
}

int main(void)
{
	int fd;
	struct input_event ev;
	fd_set readfds;
	struct timeval tv;
	int ret;
	struct timespec last_tap;
	int last_tap_was_double = 0;
	char device_path[256];
	int current_x = -1, current_y = -1;
	int in_led_zone = 0;
	int grabbed = 0;
	int led_state;

	clock_gettime(CLOCK_MONOTONIC, &last_tap);

	if (find_touchpad(device_path, sizeof(device_path)) < 0) {
		fprintf(stderr, "Failed to find touchpad device\n");
		return 1;
	}

	fd = open(device_path, O_RDWR);
	if (fd < 0) {
		perror("Failed to open touchpad device");
		return 1;
	}

	/* Check initial LED state */
	led_state = read_led_state();
	if (led_state < 0) {
		fprintf(stderr, "Failed to read LED state, assuming OFF\n");
		led_state = 0;
	}

	/* Only grab if LED is ON */
	if (led_state == 1) {
		if (ioctl(fd, EVIOCGRAB, 1) == 0) {
			grabbed = 1;
			fprintf(stderr, "LED is ON - touchpad grabbed (mouse blocked)\n");
		} else {
			perror("Failed to grab touchpad");
		}
	} else {
		fprintf(stderr, "LED is OFF - touchpad not grabbed (mouse works normally)\n");
	}

	fprintf(stderr, "Monitoring for LED button double-taps...\n");
	fprintf(stderr, "LED zone: X[%d-%d] Y[%d-%d]\n",
		LED_ZONE_X_MIN, LED_ZONE_X_MAX, LED_ZONE_Y_MIN, LED_ZONE_Y_MAX);

	while (1) {
		FD_ZERO(&readfds);
		FD_SET(fd, &readfds);
		tv.tv_sec = 0;
		tv.tv_usec = 100000; /* 100ms timeout */

		ret = select(fd + 1, &readfds, NULL, NULL, &tv);
		if (ret < 0) {
			perror("select failed");
			break;
		}

		if (ret == 0)
			continue; /* timeout */

		ret = read(fd, &ev, sizeof(ev));
		if (ret != sizeof(ev)) {
			perror("Failed to read event");
			continue;
		}

		/* Track position */
		if (ev.type == EV_ABS && ev.code == ABS_X)
			current_x = ev.value;
		if (ev.type == EV_ABS && ev.code == ABS_Y)
			current_y = ev.value;

		/* Check if touch is in LED zone */
		if (current_x >= LED_ZONE_X_MIN && current_x <= LED_ZONE_X_MAX &&
		    current_y >= LED_ZONE_Y_MIN && current_y <= LED_ZONE_Y_MAX)
			in_led_zone = 1;
		else
			in_led_zone = 0;

		/* Check for BTN_TOUCH press events in LED zone */
		if (ev.type == EV_KEY && ev.code == BTN_TOUCH && ev.value == 1) {
			struct timespec now;
			double delta_ms;

			if (!in_led_zone) {
				fprintf(stderr, "Touch outside LED zone (X=%d, Y=%d), ignoring\n",
					current_x, current_y);
				continue;
			}

			clock_gettime(CLOCK_MONOTONIC, &now);
			delta_ms = (now.tv_sec - last_tap.tv_sec) * 1000.0 +
				   (now.tv_nsec - last_tap.tv_nsec) / 1000000.0;

			fprintf(stderr, "LED button tap (X=%d, Y=%d, delta: %.0fms)\n",
				current_x, current_y, delta_ms);

			if (delta_ms < DOUBLE_TAP_WINDOW_MS && !last_tap_was_double) {
				int new_led = toggle_led();
				if (new_led >= 0) {
					/* Grab or ungrab based on new LED state */
					if (new_led == 1 && !grabbed) {
						if (ioctl(fd, EVIOCGRAB, 1) == 0) {
							grabbed = 1;
							fprintf(stderr, "LED ON - touchpad grabbed (mouse blocked)\n");
						}
					} else if (new_led == 0 && grabbed) {
						ioctl(fd, EVIOCGRAB, 0);
						grabbed = 0;
						fprintf(stderr, "LED OFF - touchpad released (mouse works)\n");
					}
				}
				last_tap_was_double = 1;
			} else {
				last_tap_was_double = 0;
			}

			last_tap = now;
		}
	}

	/* Ungrab before exit */
	if (grabbed)
		ioctl(fd, EVIOCGRAB, 0);
	close(fd);
	return 0;
}

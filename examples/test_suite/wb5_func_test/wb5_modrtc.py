# coding: utf-8
import os
import unittest
import subprocess
import time
import datetime
import sys

from wb_common.gpio import GPIO


class TestModGSMRTC(unittest.TestCase):
    rtc_root = "/sys/class/rtc/rtc1"
    GSM_POWER_GPIO = 17

    @staticmethod
    def _enable_rtc():
        subprocess.call("wb-hwconf-helper init wb55-gsm wb56-mod-rtc", shell=True)

    @staticmethod
    def _disable_rtc():
        subprocess.call("wb-hwconf-helper deinit wb55-gsm", shell=True)

    @classmethod
    def setUpClass(cls):
        print "setup class"

        try:
            GPIO.unexport(cls.GSM_POWER_GPIO)
        except:
            pass

        cls._disable_rtc()
        cls._enable_rtc()

        # get proper time from the internet
        subprocess.call("service ntp stop", shell=True)
        subprocess.call("ntpdate pool.ntp.org", shell=True)

        # set current system time to hwclock
        subprocess.call("hwclock -w", shell=True)


    def _get_rtc_ts(self):
        fname = self.rtc_root + "/since_epoch"
        return int(open(fname).read().strip())

    def test_rtc_presense(self):
        rtc_name_fname = self.rtc_root + "/name"
        self.assertTrue(os.path.exists(rtc_name_fname))
        self.assertEqual(open(rtc_name_fname).read().strip(), "mcp7940x")

    def test_ticking(self):
        delay = 5
        ts_start = self._get_rtc_ts()
        time.sleep(delay)
        ts_end = self._get_rtc_ts()

        self.assertAlmostEqual(ts_end - ts_start, delay, delta = 1)


class TestModGSMRTCFull(TestModGSMRTC):
    def test_battery(self):
        delay = 60
        self._disable_rtc()
        time.sleep(1)
        GPIO.export(self.GSM_POWER_GPIO)
        GPIO.setup(self.GSM_POWER_GPIO, GPIO.OUT)
        GPIO.output(self.GSM_POWER_GPIO, GPIO.LOW)
        time.sleep(delay)
        GPIO.unexport(self.GSM_POWER_GPIO)

        self._enable_rtc()
        ts = self._get_rtc_ts()
        dt = datetime.datetime.fromtimestamp(ts)
        self.assertGreater(dt.year, 2015)

if __name__ == '__main__':
    print "Usage: python %s [TestModGSMRTC|TestModGSMRTCFull]" % sys.argv[0]

    unittest.main()





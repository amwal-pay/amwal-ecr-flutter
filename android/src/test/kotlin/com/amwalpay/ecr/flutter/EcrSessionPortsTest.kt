package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrLogger
import kotlin.test.Test
import kotlin.test.assertIs

class EcrSessionPortsTest {

    private val logger = EcrLogger { _ -> }
    private val lanConfig = EcrTestConfigs.lan
    private val lanKey get() = lanConfig.secureHashKey

    @Test
    fun `incomplete web service plan is refused before the SDK is called`() {
        val port = EcrSessionPorts.create(
            host = "",
            serialNumber = "TW1",
            transport = EcrTransports.WEB_SERVICE,
            config = EcrConfig(
                merchantId = "",
                terminalId = "",
                secureHashKey = lanKey,
            ),
            logger = logger,
        )

        assertIs<InvalidPlanTerminalPort>(port)
    }

    @Test
    fun `ready web service plan builds an opened session`() {
        val port = EcrSessionPorts.create(
            host = "",
            serialNumber = "TW1",
            transport = EcrTransports.WEB_SERVICE,
            config = EcrTestConfigs.webService,
            logger = logger,
        )

        assertIs<SdkOpenedSessionPort>(port)
    }

    @Test
    fun `incomplete LAN plan is refused before the SDK is called`() {
        val port = EcrSessionPorts.create(
            host = "",
            serialNumber = "TW1",
            transport = EcrTransports.WIFI,
            config = lanConfig,
            logger = logger,
        )

        assertIs<InvalidPlanTerminalPort>(port)
    }

    @Test
    fun `ready LAN plan builds an opened session`() {
        val port = EcrSessionPorts.create(
            host = "192.168.1.50",
            serialNumber = "TW1",
            transport = EcrTransports.WIFI,
            config = lanConfig,
            logger = logger,
        )

        assertIs<SdkOpenedSessionPort>(port)
    }

    @Test
    fun `unsupported transport stays unsupported`() {
        val port = EcrSessionPorts.create(
            host = "192.168.1.50",
            serialNumber = "TW1",
            transport = EcrTransports.BLUETOOTH,
            config = EcrConfig(),
            logger = logger,
        )

        assertIs<UnsupportedEcrTerminalPort>(port)
    }

    @Test
    fun `USB cable without context stays unsupported`() {
        val port = EcrSessionPorts.create(
            host = "",
            serialNumber = "TW1",
            transport = EcrTransports.USB_CABLE,
            config = lanConfig,
            logger = logger,
            context = null,
        )

        assertIs<UnsupportedEcrTerminalPort>(port)
    }
}

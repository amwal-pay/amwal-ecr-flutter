package com.amwalpay.ecr.flutter

import com.amwalpay.ecr.EcrConfig
import com.amwalpay.ecr.EcrLogger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class EcrSessionPortsTest {

    private val logger = EcrLogger { _ -> }

    @Test
    fun `incomplete web service plan is refused before the SDK is called`() {
        val port = EcrSessionPorts.create(
            host = "",
            serialNumber = "TW1",
            transport = EcrTransports.WEB_SERVICE,
            config = EcrConfig(
                merchantId = "",
                terminalId = "",
                secureHashKey = "881dc200c9833da726e9376c2e32cff7",
            ),
            logger = logger,
        )

        assertIs<InvalidPlanTerminalPort>(port)
    }

    @Test
    fun `ready web service plan builds a web service terminal`() {
        val port = EcrSessionPorts.create(
            host = "",
            serialNumber = "TW1",
            transport = EcrTransports.WEB_SERVICE,
            config = EcrConfig(
                merchantId = "13593",
                terminalId = "101311",
                secureHashKey = "881dc200c9833da726e9376c2e32cff7",
            ),
            logger = logger,
        )

        assertIs<SdkWebServiceTerminal>(port)
    }

    @Test
    fun `incomplete LAN plan is refused before the SDK is called`() {
        val port = EcrSessionPorts.create(
            host = "",
            serialNumber = "TW1",
            transport = EcrTransports.WIFI,
            config = EcrConfig(
                secureHashKey = "881dc200c9833da726e9376c2e32cff7",
            ),
            logger = logger,
        )

        assertIs<InvalidPlanTerminalPort>(port)
    }

    @Test
    fun `ready LAN plan builds a LAN terminal`() {
        val port = EcrSessionPorts.create(
            host = "192.168.1.50",
            serialNumber = "TW1",
            transport = EcrTransports.WIFI,
            config = EcrConfig(
                secureHashKey = "881dc200c9833da726e9376c2e32cff7",
            ),
            logger = logger,
        )

        assertIs<SdkLanTerminal>(port)
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
}

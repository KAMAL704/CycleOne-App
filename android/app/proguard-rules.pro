# Flutter and plugin keep rules are supplied by their Gradle integrations.
# Keep this file so R8 can shrink release resources without app-specific
# reflection rules.
-dontwarn javax.imageio.spi.ImageInputStreamSpi
-dontwarn javax.imageio.spi.ImageOutputStreamSpi
-dontwarn javax.imageio.spi.ImageReaderSpi
-dontwarn javax.imageio.spi.ImageWriterSpi

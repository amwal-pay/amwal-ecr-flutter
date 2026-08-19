# The CocoaPods face of the Flutter plugin.
#
# The plugin is a bridge and nothing more: the wire protocol lives in the
# AmwalECR pod, published from AmwalECR-iOS-CocoaPods and used unchanged by
# native iOS apps. Both faces are supported — amwal_ecr/Package.swift is the
# Swift Package Manager one — and the two must name the same dependency and the
# same version range.
Pod::Spec.new do |s|
  s.name             = 'amwal_ecr'
  s.version          = '0.2.0'
  s.summary          = 'Drive an Amwal POS terminal from Flutter on iOS.'
  s.description      = <<-DESC
The iOS host for package:amwal_ecr. Adapts the platform channel onto the
AmwalECR SDK: sale, void, refund, inquiry and e-receipt.
                       DESC
  s.homepage         = 'https://github.com/amwal-pay/amwal-ecr-flutter'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Amwal Pay' => 'support@amwal-pay.com' }
  s.source           = { :path => '.' }

  s.source_files = 'amwal_ecr/Sources/amwal_ecr/**/*.swift'
  s.dependency 'Flutter'

  # Ranged to the patch line, not pinned to one version, because an app may hold
  # a native till of its own against the same SDK and CocoaPods has to resolve
  # both. The range is safe by the release policy: anything that changes what an
  # outcome means takes a major version, so 0.2.x cannot report differently from
  # what this bridge is contract-tested against.
  s.dependency 'AmwalECR', '~> 0.2.0'

  # The wrapper's floor, not the SDK's. Raise it here, in the two iOS SDK
  # repositories' manifests, in amwal_ecr/Package.swift and in the compatibility
  # matrix together.
  s.platform = :ios, '12.0'
  s.swift_version = '5.5'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end

Pod::Spec.new do |s|
  s.name     = 'FacebookClient'
  s.version  = '0.0.1'
  s.summary  = 'Library for using the Facebook SDK on iOS.'
  s.homepage = 'https://github.com/master-nevi/FacebookClient'
  s.author   = { "David Robles" => "master-nevi@users.noreply.github.com" }
  s.source   = { :git => "https://github.com/master-nevi/FacebookClient.git", :tag => s.version.to_s }
  s.source_files = 'Source/*.{h,m}'
  s.platform     = :ios, '7.0'
  s.requires_arc = true
  s.dependency 'Facebook-iOS-SDK', '~> 3.22'
end
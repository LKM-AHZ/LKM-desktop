import { RTCConfiguration, RTCIceTransportPolicy, RTCBundlePolicy } from 'libohos_webrtc.so';
// Preserve policies used by the current API; never silently turn relay-only into direct ICE.
export function applyTransportConfig(config: RTCConfiguration, values: Map<string, Object>): RTCConfiguration {
  if (values.has('iceTransportPolicy')) {
    const policy = values.get('iceTransportPolicy') as string;
    if (!['all', 'relay'].includes(policy)) throw new Error('Invalid ICE transport policy');
    config.iceTransportPolicy = policy as RTCIceTransportPolicy;
  }
  if (values.has('bundlePolicy')) {
    const policy = values.get('bundlePolicy') as string;
    if (!['balanced', 'max-bundle', 'max-compat'].includes(policy)) throw new Error('Invalid bundle policy');
    config.bundlePolicy = policy as RTCBundlePolicy;
  }
  if (values.has('rtcpMuxPolicy')) {
    if (values.get('rtcpMuxPolicy') !== 'require') throw new Error('Unsupported RTCP mux policy');
    config.rtcpMuxPolicy = 'require';
  }
  if (values.has('iceCandidatePoolSize')) {
    const size = values.get('iceCandidatePoolSize') as number;
    if (!Number.isInteger(size) || size < 0 || size > 255) throw new Error('Invalid ICE candidate pool size');
    config.iceCandidatePoolSize = size;
  }
  return config;
}

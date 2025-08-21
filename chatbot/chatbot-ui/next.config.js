/** @type {import('next').NextConfig} */
const nextConfig = {
  eslint: { ignoreDuringBuilds: true },
  typescript: { ignoreBuildErrors: true },
  images: { unoptimized: true }
};
module.exports = nextConfig;
const patch = {
  async rewrites() {
    return [
      { source: '/bridge/health', destination: 'http://api:8000/health' },
      { source: '/bridge/:path*', destination: 'http://api:8000/:path*' },
    ];
  },
};
module.exports = Object.assign({}, module.exports || {}, patch);

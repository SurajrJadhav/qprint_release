/** @type {import('next').NextConfig} */
const nextConfig = {
    // No output: 'export' — Vercel runs Next as a server; static export can cause "Cannot find module for page" during build
    images: { unoptimized: true },
    // Security headers are set in vercel.json so they apply to ALL responses (including /_next/static/*, favicon, robots.txt, sitemap.xml)
}

module.exports = nextConfig

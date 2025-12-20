import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "VoiceLearn Management Console",
  description: "Management interface for monitoring and configuring VoiceLearn services",
  icons: {
    icon: "/favicon.ico",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className="font-sans antialiased">
        {children}
      </body>
    </html>
  );
}

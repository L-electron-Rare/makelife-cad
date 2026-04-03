import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "MakeLife CAD",
  description: "Frontend Next.js pour la stack CAD FineFab"
};

export default function RootLayout({
  children
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}

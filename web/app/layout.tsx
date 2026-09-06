import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AppProvider } from "@/lib/app-context";
import { Toasts } from "@/components/ui";

export const metadata: Metadata = {
  title: "VouchFlow — voucher approvals, signed and on the record",
  description:
    "Create, review, sign, approve and track business vouchers. Configurable approval workflows, digital signatures, A4 PDF vouchers and a full audit trail.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#191817",
};

/**
 * Applied before the first paint, so a returning visitor who chose light never
 * sees a dark frame flash first (and vice versa). Dark is the default when
 * nothing has been stored.
 */
const THEME_BOOTSTRAP = `(function(){try{var t=localStorage.getItem("vouchflow.theme");document.documentElement.dataset.theme=(t==="light"||t==="dark")?t:"dark";}catch(e){document.documentElement.dataset.theme="dark";}})();`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-theme="dark" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOTSTRAP }} />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Poppins:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400;1,500&display=swap"
        />
        <link rel="stylesheet" href="https://unpkg.com/@phosphor-icons/web@2.1.1/src/duotone/style.css" />
      </head>
      <body>
        <AppProvider>
          {children}
          <Toasts />
        </AppProvider>
      </body>
    </html>
  );
}

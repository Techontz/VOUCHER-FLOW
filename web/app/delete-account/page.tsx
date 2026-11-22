"use client";

import Link from "next/link";
import { SiteFooter, SiteNav } from "@/components/landing/site-chrome";
import { CONTACT, mailto } from "@/lib/contact";

/**
 * How to delete a VouchFlow account and its data. Linked from the Google Play
 * data safety section, so it names the app, gives the steps first, and says
 * what is deleted, what is kept and for how long.
 */
export default function DeleteAccountPage() {
  return (
    <div className="lp st">
      <SiteNav />

      <header className="st-hero">
        <div className="lp-wrap">
          <h1 className="st-title">Delete your VouchFlow account</h1>
          <p className="st-sub">How to delete your account and data in the VouchFlow app and on vouchflow.co.tz, provided by TechOn Software LLC.</p>
        </div>
      </header>

      <main className="lp-wrap st-legal">
        <section>
          <h2>How to ask for deletion</h2>
          <ol>
            <li>
              Send an email to <a href={mailto(CONTACT.support, "Delete my VouchFlow account")}>{CONTACT.support}</a> from
              the email address you use to sign in, with the subject &quot;Delete my VouchFlow account&quot;.
            </li>
            <li>Say whether you want only your own user account deleted, or your whole company account and all its data (company administrators only).</li>
            <li>We confirm the request by replying to that address, and delete the account within 30 days. We email you when it is done.</li>
          </ol>
          <p>
            If you are an employee, your company&apos;s administrator can also remove your account straight away from
            Settings, Employees in VouchFlow.
          </p>
        </section>

        <section>
          <h2>What is deleted</h2>
          <ul>
            <li>Your user account: name, email, phone number, job title, password and saved signature.</li>
            <li>For a whole company account: the company profile, its users, and all its records (vouchers, stock, sales, purchasing, finance, fleet, HR and documents) and uploaded files.</li>
          </ul>
        </section>

        <section>
          <h2>What is kept, and for how long</h2>
          <ul>
            <li>
              When only one user is deleted from a company that keeps using VouchFlow, the company&apos;s business records
              that user created or approved (for example vouchers and their audit trail) stay with the company, because
              the company needs them for its accounts. They show the person&apos;s name but no longer link to an account.
            </li>
            <li>Billing and invoice records for the company&apos;s subscription are kept for up to 7 years to meet tax law.</li>
            <li>Backups are overwritten within 30 days of deletion.</li>
          </ul>
          <p>
            More about how we handle data is in our <Link href="/privacy">privacy policy</Link>.
          </p>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}

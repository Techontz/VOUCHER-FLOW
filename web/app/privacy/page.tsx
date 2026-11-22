"use client";

import { SiteFooter, SiteNav } from "@/components/landing/site-chrome";
import { CONTACT, mailto } from "@/lib/contact";

/**
 * VouchFlow's privacy policy, for the website, the web app and the Android
 * app. Plain language: what is collected, why, who sees it, how long it is
 * kept and how to reach us. Linked from the footer and from the Play listing.
 */
const UPDATED = "14 November 2026";

export default function PrivacyPage() {
  return (
    <div className="lp st">
      <SiteNav />

      <header className="st-hero">
        <div className="lp-wrap">
          <h1 className="st-title">Privacy policy</h1>
          <p className="st-sub">How VouchFlow handles the information you and your company put into it. Last updated {UPDATED}.</p>
        </div>
      </header>

      <main className="lp-wrap st-legal">
        <section>
          <h2>Who we are</h2>
          <p>
            VouchFlow is a business management platform (payment vouchers, inventory, sales, purchasing, finance,
            fleet, HR and related apps) provided by TechOn Software LLC through vouchflow.co.tz and the VouchFlow
            mobile app. For privacy questions write to <a href={mailto(CONTACT.info, "Privacy")}>{CONTACT.info}</a>.
          </p>
          <p>
            VouchFlow is used by companies. Each company decides what it records about its own staff, customers and
            suppliers; for that information the company is responsible for its use, and we process it on the
            company&apos;s behalf.
          </p>
        </section>

        <section>
          <h2>What we collect</h2>
          <ul>
            <li><strong>Account details:</strong> your name, work email, phone number, job title, department and role, and a password (stored only as a secure hash).</li>
            <li><strong>Company details:</strong> company name, address, tax and registration numbers, bank details printed on vouchers, logo and brand colours.</li>
            <li><strong>Business records you create:</strong> vouchers, approvals and signatures, payments, products and stock, orders and invoices, customers and suppliers, vehicles and trips, employee, leave, attendance and payroll records, and documents.</li>
            <li><strong>Files you choose to upload:</strong> photos taken with the camera or picked from the device, and documents, only when you attach them.</li>
            <li><strong>Activity records:</strong> an audit trail of who did what and when, sign-in times and the device&apos;s IP address, used for security and accountability.</li>
          </ul>
          <p>We do not collect your location, contacts or advertising identifiers, we do not show ads, and we do not sell personal information.</p>
        </section>

        <section>
          <h2>Why we use it</h2>
          <ul>
            <li>To provide the service: sign you in, show you the apps your company allows, and keep your company&apos;s records.</li>
            <li>To send messages the service needs, such as invitations, password resets, approval requests and expiry reminders.</li>
            <li>To keep the platform secure, prevent misuse and keep an accurate audit trail.</li>
            <li>To bill your company for its subscription.</li>
          </ul>
        </section>

        <section>
          <h2>Who can see it</h2>
          <p>
            Each company&apos;s data is kept separate from every other company&apos;s. Inside a company, people see only what
            their role allows. VouchFlow staff access a company&apos;s data only to support it or to keep the service running.
          </p>
          <p>
            We use service providers to run VouchFlow: our hosting provider in Tanzania, and an email delivery service for
            system emails. They process data only for us. We disclose information if the law requires it.
          </p>
        </section>

        <section>
          <h2>How we protect and keep it</h2>
          <p>
            Data is sent over encrypted connections (HTTPS) and stored on secured servers with regular backups. We keep a
            company&apos;s records for as long as its account is active, and as needed afterwards for legal, tax and audit
            purposes. A company can ask us to delete its account and data.
          </p>
        </section>

        <section>
          <h2>Your choices</h2>
          <p>
            You can see and update your profile in the app. To correct or delete other information about you, ask your
            company&apos;s administrator, or write to us at <a href={mailto(CONTACT.info, "Privacy request")}>{CONTACT.info}</a> and
            we will help. To delete your account, ask your company&apos;s administrator or email us from the address on the account.
          </p>
        </section>

        <section>
          <h2>Children</h2>
          <p>VouchFlow is a workplace tool and is not meant for children under 18.</p>
        </section>

        <section>
          <h2>Changes</h2>
          <p>If we change this policy we will update the date above, and tell company administrators about important changes.</p>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}

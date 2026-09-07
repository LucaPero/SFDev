// Generates AdaptAbility_Knowledge_Articles.csv — standard-field-only Knowledge article
// records for the AdaptAbility agent (Everline). Run with: node generate-articles.js
"use strict";
const fs = require("fs");
const path = require("path");

// ---------- Domains ----------
// Each domain: [ "Domain Label", audience, [ [title, bodyHtml], ... ] ]
// audience is one of "employee", "customer", "both" — drives IsVisibleInPkb/Csp.
// bodyHtml goes into the standard "Summary" (rich text) field.

const P = (s) => `<p>${s}</p>`;
const OL = (items) => `<ol>${items.map((i) => `<li>${i}</li>`).join("")}</ol>`;

const ACCOMMODATIONS = [
  ["Requesting a Workplace Accommodation", P("Any Everline employee can request a workplace accommodation at any time, whether the need is physical, sensory, cognitive, or related to a medical condition.") + OL(["Submit a request through the Accommodations portal or ask AdaptAbility to connect you with a People Success specialist.","A specialist reaches out within 2 business days to start the interactive process.","Together you identify one or more reasonable accommodations that address the need.","Approved accommodations are implemented, and you're notified when equipment or changes are in place."]) + P("You do not need a diagnosis to start the conversation — describing the functional limitation is enough to begin.")],
  ["Ergonomic Equipment Available at Everline", P("Everline provides standing desks, ergonomic chairs, split and vertical keyboards, and monitor arms to any employee who requests them for comfort or medical reasons — no manager approval is required for standard ergonomic equipment. Requests are submitted through the Accommodations portal and typically ship within 5-7 business days. Employees working from an Everline office can also book a walkthrough with a workplace ergonomics specialist before choosing equipment.")],
  ["Getting Noise-Cancelling Headphones", P("Noise-cancelling headphones are pre-approved equipment at Everline — any employee, with or without a stated medical reason, can request a pair through the Accommodations portal without going through the interactive process. This is one of the few accommodations that ships automatically without a specialist conversation, since it has no meaningful cost or workspace impact for coworkers.")],
  ["Screen Reader and Assistive Software Setup", P("Everline-issued laptops come with JAWS, NVDA, or VoiceOver available for installation through the internal Software Center at no additional approval step. IT can pre-configure a new laptop with your preferred screen reader before it ships if you let the Accommodations team know in advance. If a specific work application doesn't behave correctly with your screen reader, report it as a troubleshooting case rather than a new accommodation request — screen reader compatibility issues in existing tools are handled as bugs, not new requests.")],
  ["Requesting a Sit-Stand Desk", P("Sit-stand desks are available to any employee working from an Everline office or on a home-office stipend, whether for a documented medical need or general preference. Requests submitted through the Accommodations portal are fulfilled within 5-7 business days for office locations; home-office requests are reimbursed against the standard equipment stipend rather than shipped directly.")],
  ["Alternative Input Devices", P("Trackballs, foot pedals, single-switch devices, and voice-control software (such as Dragon NaturallySpeaking) are all available as accommodations for employees who need an alternative to a standard mouse and keyboard. These typically go through a brief interactive-process conversation with a People Success specialist to confirm the right device for your specific need, since there's more than one option and getting it right the first time avoids a return.")],
  ["Booking a Quiet or Focus Room", P("Every Everline office has at least one quiet room bookable through the same calendar system used for meeting rooms, intended for employees who need a low-sensory environment to focus or decompress. Quiet rooms are first-come, first-served for anyone, but employees with an approved sensory accommodation can request a standing reservation for the same time each day.")],
  ["How Long Does an Accommodation Request Take?", P("Most equipment-only accommodations (ergonomic gear, headphones, screen readers) ship within 5-7 business days of the request. Accommodations requiring the interactive process — a schedule change, a role modification, or anything needing a specialist conversation — typically resolve within 2-3 weeks from first contact, though this varies with complexity. If a request is time-sensitive (a safety concern or a near-term deadline), say so explicitly when you submit it so it can be prioritized.")],
  ["Temporary vs. Permanent Accommodations", P("Accommodations can be requested as temporary (for example, during recovery from a surgery or a short-term injury) or permanent. Temporary accommodations are reviewed at an agreed end date rather than requiring a brand-new request, and can be extended if the underlying need continues. Permanent accommodations are reviewed periodically (typically annually) simply to confirm they still meet your needs, not to re-justify the original request.")],
  ["Accommodations for Vision or Hearing Needs", P("Employees who are blind, have low vision, are Deaf, or are hard of hearing can request screen magnification software, screen readers, captioning services for live meetings, ASL interpretation for scheduled meetings, or amplified/visual alert devices. Live-meeting captioning and interpretation should be requested at least 48 hours in advance through the Accommodations portal so a vendor can be scheduled.")],
];

const FLEXIBLE_WORK = [
  ["Requesting a Compressed Work Schedule", P("A compressed schedule (for example, four 10-hour days instead of five 8-hour days) can be requested through your manager and confirmed with People Success — most roles are eligible unless the role specifically requires daily availability during standard business hours (e.g. certain customer-facing support roles). Compressed schedules are typically approved on a 60-day trial basis before being made permanent.")],
  ["Core Hours and Flexible Start/End Times", P("Everline's core collaboration hours are 10am-3pm in your local time zone — outside that window, employees can start and end their day whenever works best for them, as long as weekly hours and meeting commitments are met. This applies company-wide by default; no request is needed unless you want a schedule that falls outside even the flexible boundaries (for example, working exclusively evenings).")],
  ["Fully Remote Work Arrangements", P("Employees can request a fully remote arrangement even if their role is nominally office-based, subject to manager approval and any role-specific requirements. Requests are submitted through the Flexible Work portal and typically reviewed within one week. A fully remote arrangement does not require a medical or accommodation justification — it can be requested for any reason, though accommodation-driven requests are prioritized for faster review.")],
  ["Hybrid Schedule Options", P("Hybrid employees can choose which days they come into an Everline office, as long as they overlap with their immediate team's designated in-office day at least once per week. Hybrid schedules are set with your manager directly and don't require a formal Flexible Work portal request unless you need an exception to the team's designated day.")],
  ["Asynchronous Communication Norms at Everline", P("Everline treats most work communication as asynchronous by default: messages don't require an immediate reply, and 'urgent' should be reserved for things that actually can't wait. This norm exists specifically to support employees across time zones and those who work non-standard hours as part of an approved flexible arrangement — replying within your own working hours is expected, not replying instantly.")],
  ["Focus Time Blocks and Calendar Etiquette", P("Employees are encouraged to block 2+ hour focus periods on their calendar, visible to teammates as 'Focus Time — will respond after,' and Everline's calendar tooling automatically suggests avoiding meeting invites during marked focus blocks. This is available to everyone, but is specifically recommended as a first step for employees who've mentioned difficulty concentrating amid frequent meetings.")],
  ["Adjusting Your Schedule for Caregiving", P("Employees with caregiving responsibilities (children, aging relatives, or other dependents) can request a modified schedule — shifted hours, a mid-day break, or a compressed week — through the same Flexible Work process used for any other schedule change. No documentation of the caregiving relationship is required to start the conversation.")],
  ["Time Zone Considerations for Distributed Teams", P("Teams spanning more than 3 time zones are expected to rotate meeting times so the same people aren't always attending outside their working hours, and to record meetings for anyone who can't attend live. If your team isn't following this norm, raise it with your manager — it's a stated expectation, not just a suggestion.")],
  ["Trial Periods for New Schedule Arrangements", P("New flexible-work arrangements (compressed schedules, fully remote shifts, non-standard hours) are typically approved on a 60-day trial before being made permanent, giving both the employee and manager a chance to confirm it works in practice. Either side can end the trial early and revert to the previous schedule without it counting against a future request.")],
];

const LEAVE_BENEFITS = [
  ["Starting a Medical or Disability Leave Request", P("Medical and disability leave requests start with a conversation with People Success, either directly or through AdaptAbility — you do not need to go through your manager first, and your manager will only be told that you're on leave, not the medical reason unless you choose to share it.") + OL(["Contact People Success or ask AdaptAbility to start a leave request.","Provide the expected start date and, if known, expected duration.","Submit supporting medical documentation if the leave exceeds 5 consecutive days.","People Success confirms your leave type, pay treatment, and return-to-work expectations in writing."])],
  ["What Is the Interactive Process?", P("The interactive process is the required back-and-forth conversation between an employee and People Success to identify a reasonable accommodation once a need is raised — it's not a one-time form, but an ongoing dialogue until a workable solution is found or determined not to exist. Everline documents each interactive-process conversation so there's a clear record of what was discussed and agreed, but the conversation itself can happen over email, phone, or in person, whatever's more comfortable.")],
  ["Return-to-Work Planning", P("Before returning from a medical or disability leave, People Success schedules a return-to-work conversation to confirm any accommodations needed for the transition (a phased return, a modified schedule, or equipment) are in place before your first day back. If your return date changes, notify People Success as early as possible — a delayed return does not need to be re-justified from scratch, just confirmed.")],
  ["Employee Assistance Program (EAP) Overview", P("Everline's EAP provides free, confidential counseling sessions (up to 8 per issue per year), financial and legal consultation, and referrals to specialists, available to all employees and their household members regardless of whether they're enrolled in Everline's health plan. EAP usage is completely confidential — Everline never receives information about who used the program or why, only aggregate utilization statistics.")],
  ["Intermittent Leave for Ongoing Conditions", P("Employees with a chronic condition that periodically prevents them from working (for example, migraines, flare-ups of an autoimmune condition, or ongoing treatment appointments) can be approved for intermittent leave — taken in smaller increments as needed rather than one continuous block. Intermittent leave is set up once with People Success and then self-reported each time it's used, rather than requiring a new request every time.")],
  ["How Leave Affects Your Pay and Benefits", P("Short-term disability leave is paid at 60% of base salary for up to 12 weeks; benefits enrollment (health, dental, vision) continues unaffected during any approved leave. Unpaid leave beyond what's covered by short-term disability or accrued PTO can be arranged with People Success on a case-by-case basis. Specific pay calculations depend on your role and tenure — People Success will confirm your exact figures when you start a leave request.")],
  ["Documentation Needed for a Leave Request", P("Leave requests under 5 consecutive days generally don't require medical documentation. Leave of 5 or more consecutive days requires a healthcare provider's note confirming the need for leave and, where relevant, an expected duration — the note does not need to disclose your specific diagnosis, only the functional need and timeframe.")],
  ["Extending an Existing Leave", P("To extend a leave already in progress, contact People Success before your originally scheduled return date with an updated healthcare provider's note reflecting the new expected duration. Extensions do not require restarting the interactive process from scratch — they're treated as a continuation of the existing case.")],
  ["Confidentiality of Leave and Medical Information", P("Medical documentation submitted for a leave or accommodation request is stored separately from your general personnel file and is only accessible to People Success staff directly handling your case — not to your manager or team. Your manager is informed only of the dates and general nature (e.g. 'medical leave') needed to manage staffing, never the underlying medical details.")],
];

const MANAGER_ENABLEMENT = [
  ["Supporting a Team Member's Accommodation Without Oversharing", P("When a team member receives an approved accommodation, managers are told only what's needed to implement it operationally (for example, 'this person will work a compressed schedule on Mondays') — never the underlying medical reason, which stays confidential with People Success. If teammates ask why someone's schedule or setup is different, the appropriate response is a general one ('we support flexible arrangements for a variety of reasons') rather than any explanation specific to that person.")],
  ["What Managers Can and Cannot Ask About a Disability", P("Managers should never ask an employee to disclose a diagnosis, request to see medical documentation directly, or ask probing questions about the nature of a disability — all of that goes through People Success. A manager can ask what's needed to do the job effectively and can discuss how an approved accommodation will be implemented, but the medical justification itself is never the manager's business to evaluate.")],
  ["Approving Flexible Schedule Requests as a Manager", P("Most flexible-schedule requests (compressed weeks, hybrid day changes, shifted hours) can be approved directly by a manager without involving People Success, as long as the request doesn't conflict with a role-specific requirement. If you're unsure whether a request is compatible with the role's requirements, or if the employee frames it as a medical need, loop in People Success rather than guessing.")],
  ["Recognizing Signs a Team Member May Need Support", P("Noticeable changes in a team member's work pattern, communication style, or engagement can sometimes indicate an unmet accommodation need, but managers should not diagnose or assume — the appropriate step is a general, supportive check-in ('I've noticed X, how are you doing, is there anything that would help?') rather than asking directly about a health condition. If the employee raises something that sounds like it could be accommodation-related, point them to People Success or AdaptAbility rather than trying to resolve it yourself.")],
  ["Manager's Role in the Interactive Process", P("Managers are sometimes included in specific parts of the interactive process — confirming whether a proposed accommodation is operationally workable for the team, for example — but People Success leads the conversation and makes the final determination. A manager's role is to answer operational questions honestly, not to approve or deny the accommodation itself.")],
  ["Building an Inclusive Team Culture", P("Simple team norms — sharing meeting agendas in advance, defaulting to captions on recorded content, avoiding scheduling over known focus blocks, and normalizing flexible participation (camera-off, async responses) — reduce the number of individual accommodation requests needed in the first place by building accessibility into how the team already works. Managers are encouraged to set these as team defaults rather than case-by-case accommodations.")],
  ["Handling Team Questions About a Colleague's Accommodation", P("If a teammate asks a manager why a colleague has a different schedule, setup, or working pattern, the correct response is a brief, general statement about Everline supporting varied working arrangements — never confirming or speculating about a specific colleague's situation, even if the manager knows the details. Redirect persistent questions to People Success if needed.")],
  ["Manager Training Resources on Neurodiversity", P("Everline offers an optional but recommended manager training module on supporting neurodivergent team members — covering communication preferences, meeting structure adjustments, and how to give feedback in a way that works for different cognitive styles. It's available on-demand through the Learning Hub and takes about 45 minutes.")],
];

const PRODUCT_ACCESSIBILITY = [
  ["Screen Reader Support in Everline", P("Everline's web and desktop apps are compatible with JAWS, NVDA, and VoiceOver across the dashboard, task boards, and messaging surfaces. All interactive elements have labeled ARIA roles and keyboard-reachable focus order. The one known gap is the analytics chart view, which does not yet have a text-equivalent data summary — a workaround is exporting the underlying data as a table, which is fully screen-reader accessible.")],
  ["Keyboard Navigation Shortcuts", P("Every action reachable by mouse in Everline is also reachable by keyboard: Tab and Shift+Tab move focus, Enter or Space activates a focused control, and Escape closes any open dialog or menu. A full shortcut reference is available in-app under Help > Keyboard Shortcuts, and can be customized per-user under Settings > Accessibility.")],
  ["High-Contrast and Dark Mode Display Settings", P("Everline offers a high-contrast theme (in addition to standard light and dark modes) under Settings > Appearance, designed to meet WCAG AA contrast ratios throughout the interface, including on custom-colored task labels. The high-contrast theme can be set to apply automatically based on your operating system's accessibility settings.")],
  ["Captions and Transcripts for Video Content", P("All Everline product tutorial videos and recorded webinars include auto-generated captions, reviewed for accuracy before publishing, plus a downloadable full transcript. Live webinars include real-time captioning; if you need ASL interpretation for a live session, request it at least 48 hours in advance through the registration form.")],
  ["Adjusting Text Size and Zoom", P("Everline's interface respects your browser's zoom level up to 400% without breaking layout or losing functionality, and also offers an in-app text-size control under Settings > Appearance independent of browser zoom. Both can be used together if you need larger text than either provides alone.")],
  ["Color-Blind Friendly Palette Option", P("Status indicators (task priority, project health, notification badges) that normally rely on red/green/yellow coloring have an alternate color-blind-friendly palette available under Settings > Appearance > Color Palette, which also adds distinct icon shapes to each status so color isn't the only signal.")],
  ["Reduced Motion Setting", P("Enabling Reduced Motion under Settings > Accessibility disables non-essential animations (page transitions, hover effects, loading spinners with motion) throughout Everline, replacing them with instant state changes or a simple static indicator. This setting also respects your operating system's reduced-motion preference automatically if one is set.")],
  ["Voice Control Compatibility", P("Everline's web app works with Voice Control on macOS and Voice Access on Windows/Android for navigation and text entry, since all interactive elements have accessible, speakable labels. Voice-driven text entry into task descriptions and comments is fully supported; voice-driven drag-and-drop reordering of tasks is not yet supported and requires a mouse, keyboard, or switch device instead.")],
  ["Accessibility Roadmap and Known Gaps", P("Everline publishes a public accessibility roadmap listing known gaps (currently: the analytics chart text-summary gap and voice-driven drag-and-drop) along with target resolution quarters. Customers can subscribe to updates on a specific gap and are notified directly when it ships, rather than needing to check back manually.")],
];

const CUSTOMER_ACCOMMODATION_REQUESTS = [
  ["Requesting Invoices in an Accessible Format", P("Customers who need invoices in an alternate format — large print, a screen-reader-optimized layout, or Braille — can request this once through Support, and all future invoices will automatically generate in the requested format going forward, not just the current one.")],
  ["Sign Language Interpretation for Support Calls", P("ASL interpretation can be arranged for any scheduled support call by requesting it when you book the call, ideally at least 48 hours in advance so a qualified interpreter can be scheduled. For urgent unscheduled support needs, live chat and email support remain immediately available as alternatives while an interpreted call is arranged.")],
  ["Extended Response Time Accommodations", P("Customers who need more time to review and respond to support communications — for example, due to a cognitive or processing-related need — can request an extended-response-time flag on their account, which pauses any support-ticket auto-closure timers that would otherwise apply after a period of inactivity.")],
  ["Requesting Documentation in Plain Language", P("Any Everline help article or product documentation page can be requested in a plain-language rewrite through Support — this is a manual process handled by the documentation team, typically completed within 5 business days, and the plain-language version is then published for all customers to benefit from, not just the requester.")],
  ["Alternative Contact Methods for Support", P("Beyond standard chat and email, customers can request phone-only support, text-relay support for Deaf or hard-of-hearing customers, or a designated single point of contact for ongoing complex issues rather than being routed to a different agent each time.")],
  ["Accessible Onboarding Sessions", P("New customer onboarding sessions can be customized on request — screen-reader-compatible screen-sharing tools, captioning, extended session length, or a written follow-up summary in place of a live walkthrough. Mention the need when scheduling onboarding so the session can be set up correctly in advance.")],
  ["How to Submit a Vendor Accommodation Request", P("Any accommodation request related to how your organization interacts with Everline as a vendor — accessible contracting documents, accessible billing processes, or accommodations for your own team members who interact with Everline support — can be submitted through Support or directly to your account manager if you have one.")],
];

const POLICY_PRIVACY_RIGHTS = [
  ["Is My Accommodation Request Confidential?", P("Yes — accommodation and leave records are stored separately from your general personnel file and are only accessible to the People Success staff directly handling your case. Your manager is told only what's operationally necessary to implement an approved accommodation, never the underlying medical or personal reason.")],
  ["Appealing a Denied Accommodation Request", P("If an accommodation request is denied or only partially approved, you can appeal the decision by requesting a review from a different People Success specialist than the one who made the original determination.") + OL(["Submit an appeal request within 30 days of the original decision.","State specifically what you're appealing and why.","A different specialist reviews the case, including any new information you provide.","You'll receive a written decision within 10 business days of the appeal being submitted."])],
  ["Non-Retaliation Policy", P("Everline prohibits retaliation against any employee or customer for requesting an accommodation, participating in the interactive process, or raising a concern about how a request was handled. Reports of suspected retaliation are investigated by a team independent of the reporting employee's management chain.")],
  ["Your Rights Under Disability Accommodation Law", P("Employees and customers have the right to request reasonable accommodations for a disability without being required to disclose a specific diagnosis, to have that request considered through a genuine interactive process, and to appeal a denial. Everline's policy is designed to meet or exceed applicable disability-rights law in every jurisdiction where it operates, and specific legal rights can vary by location — a People Success specialist can clarify what applies to your specific situation.")],
  ["Who Has Access to My Accommodation Records?", P("Only People Success staff directly assigned to your case can view your accommodation or leave records. IT support staff who provision approved equipment see only what's needed to fulfill the equipment request (for example, 'ship a standing desk'), never the underlying medical justification.")],
  ["How Long Are Accommodation Records Retained?", P("Accommodation and leave records are retained for the duration of employment plus a legally required minimum retention period afterward (which varies by jurisdiction), then securely deleted. You can request a copy of what's retained about you at any time — see 'Requesting a Copy of Your Accommodation File.'")],
  ["Reasonable Accommodation vs. Undue Hardship", P("Everline is required to provide a reasonable accommodation unless doing so would impose an undue hardship — a significant difficulty or expense relative to Everline's size and resources. In practice, this standard is rarely reached: nearly all requested accommodations (equipment, schedule changes, software) are approved. If a specific requested accommodation genuinely can't be provided, People Success is required to work with you to identify an alternative that does meet the need.")],
  ["Requesting a Copy of Your Accommodation File", P("You can request a full copy of your own accommodation or leave file at any time by contacting People Success directly — this is your record and you're entitled to see it in full, including any documentation you submitted and any determinations made. Requests are typically fulfilled within 10 business days.")],
];

const TROUBLESHOOTING = [
  ["My Approved Equipment Never Arrived", P("If approved accommodation equipment hasn't arrived within the expected 5-7 business day window, contact People Success with your request date — most delays are a shipping issue that can be resolved with expedited reshipping, not a problem with the approval itself, which remains valid.")],
  ["Screen Reader Stopped Working After an Update", P("If a screen reader that previously worked correctly with Everline stops behaving properly after a product update, this is treated as a bug, not a new accommodation request — report it through Support with your screen reader name/version so the accessibility engineering team can reproduce and fix it, typically prioritized above standard bug-fix timelines.")],
  ["Accessibility Setting Reverted After a Product Update", P("Occasionally a product update can reset a personal accessibility setting (high-contrast theme, reduced motion, text size) back to its default. Re-applying the setting under Settings > Accessibility resolves it immediately; if it happens repeatedly after every update, report it to Support so it can be fixed at the source.")],
  ["Flexible Schedule Not Reflected in the Time Tracking System", P("If your approved flexible schedule isn't correctly reflected in Everline's internal time-tracking tool (for example, it's still flagging a compressed-schedule day as an anomaly), this is an IT/systems sync issue, not a problem with the accommodation approval itself — report it to IT Support with your approval confirmation so they can correct the system record.")],
  ["Focus Room Booking System Not Working", P("If the focus/quiet room booking calendar is unavailable or won't accept a booking, check the office's shared calendar directly as a fallback, and report the booking-system issue to IT Support. A standing reservation tied to an approved accommodation should never be lost due to a booking-system outage — flag it immediately if that happens.")],
  ["Captions Missing on a Specific Video", P("If a specific Everline tutorial or webinar recording is missing captions or has visibly inaccurate captions, report the specific video link to Support — this is treated as a documentation gap to be fixed directly, and does not require a new accessibility request each time.")],
  ["Approved Accommodation Not Yet Implemented", P("If an accommodation was approved but hasn't actually been put in place after a reasonable time (equipment shipped but schedule not updated, for example), contact the People Success specialist who handled your original request directly rather than starting a new request — this is a follow-up on an existing approved case, and should be resolved quickly since the determination has already been made.")],
];

const DOMAINS = [
  ["Workplace Accommodations & Assistive Technology", "employee", ACCOMMODATIONS],
  ["Flexible Work Arrangements", "employee", FLEXIBLE_WORK],
  ["Leave & Benefits", "employee", LEAVE_BENEFITS],
  ["Manager & Team Enablement", "employee", MANAGER_ENABLEMENT],
  ["Product Accessibility Features", "customer", PRODUCT_ACCESSIBILITY],
  ["Customer Accommodation Requests", "customer", CUSTOMER_ACCOMMODATION_REQUESTS],
  ["Accommodation Policy, Privacy & Rights", "both", POLICY_PRIVACY_RIGHTS],
  ["Troubleshooting", "both", TROUBLESHOOTING],
];

// ---------- Build records ----------
function slugify(title) {
  return title
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

const seenSlugs = new Set();
function uniqueSlug(title) {
  let base = slugify(title);
  let slug = base;
  let n = 2;
  while (seenSlugs.has(slug)) {
    slug = `${base}-${n}`;
    n++;
  }
  seenSlugs.add(slug);
  return slug;
}

function csvEscape(value) {
  const s = String(value);
  return `"${s.replace(/"/g, '""')}"`;
}

// audience -> [IsVisibleInPkb, IsVisibleInCsp] ; IsVisibleInPrm is always FALSE
const VISIBILITY_BY_AUDIENCE = {
  employee: ["TRUE", "FALSE"],
  customer: ["FALSE", "TRUE"],
  both: ["TRUE", "TRUE"],
};

const rows = [];
for (const [domainLabel, audience, articles] of DOMAINS) {
  const [pkb, csp] = VISIBILITY_BY_AUDIENCE[audience];
  for (const [title, body] of articles) {
    rows.push({
      Title: title,
      UrlName: uniqueSlug(title),
      Summary: body,
      Language: "en_US",
      IsVisibleInPkb: pkb,
      IsVisibleInCsp: csp,
      IsVisibleInPrm: "FALSE",
      __domain: domainLabel,
    });
  }
}

const headers = ["Title", "UrlName", "Summary", "Language", "IsVisibleInPkb", "IsVisibleInCsp", "IsVisibleInPrm"];
const csvLines = [headers.join(",")];
for (const r of rows) {
  csvLines.push(headers.map((h) => csvEscape(r[h])).join(","));
}

const outDir = path.join(__dirname, "..");
const outFile = path.join(outDir, "AdaptAbility_Knowledge_Articles.csv");
fs.writeFileSync(outFile, csvLines.join("\r\n"), "utf8");

// Per-domain counts for verification
const counts = {};
for (const r of rows) counts[r.__domain] = (counts[r.__domain] || 0) + 1;

console.log(`Wrote ${rows.length} article records to ${outFile}`);
console.log("Per-domain counts:");
for (const [domain, , articles] of DOMAINS) {
  console.log(`  ${domain}: ${counts[domain]}`);
}
console.log(`Unique UrlNames: ${seenSlugs.size}`);

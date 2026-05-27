import { redirect } from "next/navigation";

// The middleware guard handles auth; an authenticated super-admin hitting "/"
// lands on the Health dashboard.
export default function Home() {
  redirect("/health");
}

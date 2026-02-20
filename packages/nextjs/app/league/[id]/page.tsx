import LeagueDetailClient from "./LeagueDetailClient";

export function generateStaticParams() {
  return Array.from({ length: 100 }, (_, i) => ({ id: String(i) }));
}

const LeagueDetailPage = async ({ params }: { params: Promise<{ id: string }> }) => {
  const { id } = await params;
  return <LeagueDetailClient id={id} />;
};

export default LeagueDetailPage;

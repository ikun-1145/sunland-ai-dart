// The old activation-code product is retired. This source intentionally has no
// service-role client or database write path; deployment remains a separately
// confirmed production action.
Deno.serve(() =>
  new Response(
    JSON.stringify({ error: "ACTIVATION_CODES_RETIRED" }),
    {
      status: 410,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
      },
    },
  ),
);

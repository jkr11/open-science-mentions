for PAGE in {1..5}; do
  curl "https://api.openalex.org/works?page=${PAGE}&filter=primary_location.source.id:s26220619|s133489141|s136622136|s38537713|s193250556|s93932044|s2738745139|s27825752|s2764729928|s171182518,open_access.is_oa:true,has_content.pdf:true&sort=cited_by_count:desc&per_page=10&mailto=ui@openalex.org"
done
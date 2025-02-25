
sudo apt-get install bubblewrap
wget https://github.com/ocaml/opam/releases/download/2.3.0/opam-full-2.3.0.tar.gz
tar -xf opam-full-2.3.0.tar.gz
cd opam-full-2.3.0/
make cold
sudo make cold-install
opam init --disable-sandboxing
opam install ocaml
eval $(opam env)
# Verify installation
ocaml --version
dune --version
# Tooling
opam install dune ocaml-lsp-server odoc ocamlformat utop

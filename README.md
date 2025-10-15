# ONE COMMAND INSTALL
curl -sSL https://raw.githubusercontent.com/be2aja/genieacs-ubuntu22.04/main/deploy.sh | sudo bash

# Manual 
1. install genieacs

    wget https://raw.githubusercontent.com/be2aja/genieacs-ubuntu22.04/main/install-genieacs.sh
   
    chmod +x *.sh
    
    sudo ./install-genieacs.sh

    

3. restore data

     docker wget https://raw.githubusercontent.com/be2aja/genieacs-ubuntu22.04/main/restore-genieacs-data.sh

   chmod +x *.sh
    
      sudo ./restore-genieacs-data.sh

     native or docker wget https://raw.githubusercontent.com/be2aja/genieacs-ubuntu22.04/main/restore-genieacs.sh

     chmod +x *.sh
    
      sudo ./restore-genieacs.sh

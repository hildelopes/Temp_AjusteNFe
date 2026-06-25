*&---------------------------------------------------------------------*
*& Report  ZREPORT_AJUSTE_NFE
*& Ajuste de NF-e: Anula status, executa BDC de ajuste (J1B2N)
*& e reenvia para autorização via J1BNFE.
*&---------------------------------------------------------------------*
REPORT zreport_ajuste_nfe.

*----------------------------------------------------------------------*
* Tabelas
*----------------------------------------------------------------------*
TABLES: j_1bnfdoc.

*----------------------------------------------------------------------*
* Tipos
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_nfdoc,
         docnum  TYPE j_1bnfdoc-docnum,
         series  TYPE j_1bnfdoc-series,
         docdat  TYPE j_1bnfdoc-docdat,
         pstdat  TYPE j_1bnfdoc-pstdat,
         nfenum  TYPE j_1bnfdoc-nfenum,
       END OF ty_nfdoc.

TYPES: BEGIN OF ty_nflin,
         docnum     TYPE j_1bnflin-docnum,
         itmnum     TYPE j_1bnflin-itmnum,
         itmtyp     TYPE j_1bnflin-itmtyp,
         charg      TYPE j_1bnflin-charg,
         cfop       TYPE j_1bnflin-cfop,
         taxlw1     TYPE j_1bnflin-taxlw1,
         matorg     TYPE j_1bnflin-matorg,
         taxlw2     TYPE j_1bnflin-taxlw2,
         taxlw4     TYPE j_1bnflin-taxlw4,
         nbm        TYPE j_1bnflin-nbm,
         taxlw5     TYPE j_1bnflin-taxlw5,
         classtrib  TYPE j_1bnflin-classtrib,
         cod_cta    TYPE j_1bnflin-cod_cta,
         num_item   TYPE j_1bnflin-num_item,
         menge_trib TYPE j_1bnflin-menge_trib,
         meins_trib TYPE j_1bnflin-meins_trib,
       END OF ty_nflin.

*----------------------------------------------------------------------*
* Dados globais
*----------------------------------------------------------------------*
DATA: gs_nfdoc   TYPE ty_nfdoc,
      gt_nflin   TYPE TABLE OF ty_nflin,
      gs_nflin   TYPE ty_nflin,
      gt_bdcdata TYPE TABLE OF bdcdata,
      gs_bdcdata TYPE bdcdata,
      gt_bdcmsg  TYPE TABLE OF bdcmsgcoll,
      gs_bdcmsg  TYPE bdcmsgcoll,
      gv_mode    TYPE c VALUE 'N',   " N=Background, A=Foreground, E=Stop on error
      gv_docnum  TYPE j_1bnfdoc-docnum,
      gv_date    TYPE sy-datum,
      gv_date_f  TYPE char10,
      gv_menge_f TYPE char18.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_docnum TYPE j_1bnfdoc-docnum OBLIGATORY,
              p_mode   TYPE c DEFAULT 'N'.   " N=Batch, A=Foreground
SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* Initialization
*----------------------------------------------------------------------*
INITIALIZATION.
  TEXT-001 = 'Parâmetros de Execução'.

*----------------------------------------------------------------------*
* Start-of-selection
*----------------------------------------------------------------------*
START-OF-SELECTION.

  gv_docnum = p_docnum.
  gv_mode   = p_mode.

  " 1) Buscar dados da NF-e
  PERFORM f_get_nfe_data.

  " 2) Anular status do documento na J1BNFE
  PERFORM f_anular_status.

  " 3) Executar BDC de ajuste (J1B2N)
  PERFORM f_bdc_ajuste.

  " 4) Reenviar para autorização na J1BNFE
  PERFORM f_reenviar_autorizacao.

*----------------------------------------------------------------------*
* Forms
*----------------------------------------------------------------------*
FORM f_get_nfe_data.

  SELECT SINGLE docnum series docdat pstdat nfenum
    INTO CORRESPONDING FIELDS OF gs_nfdoc
    FROM j_1bnfdoc
   WHERE docnum = gv_docnum.

  IF sy-subrc <> 0.
    MESSAGE |Documento { gv_docnum } não encontrado na J_1BNFDOC.| TYPE 'E'.
  ENDIF.

  SELECT docnum itmnum itmtyp charg cfop taxlw1 matorg taxlw2
         taxlw4 nbm taxlw5 classtrib cod_cta num_item menge_trib meins_trib
    INTO CORRESPONDING FIELDS OF TABLE gt_nflin
    FROM j_1bnflin
   WHERE docnum = gv_docnum.

  IF sy-subrc <> 0.
    MESSAGE |Nenhum item encontrado para o documento { gv_docnum }.| TYPE 'E'.
  ENDIF.

ENDFORM.

*----------------------------------------------------------------------*
* Anular status do documento via J1BNFE (função BAPI/RFC ou BDC)
*----------------------------------------------------------------------*
FORM f_anular_status.

  DATA: lt_bdcdata TYPE TABLE OF bdcdata,
        ls_bdcdata TYPE bdcdata,
        lt_bdcmsg  TYPE TABLE OF bdcmsgcoll,
        lv_okcode  TYPE sy-ucomm.

  " Tela inicial J1BNFE - buscar documento
  PERFORM f_bdc_dynpro  USING 'SAPMJ1B1'  '1100'
                        CHANGING lt_bdcdata.
  PERFORM f_bdc_field   USING 'BDC_CURSOR'     'J_1BDYDOC-DOCNUM'
                        CHANGING lt_bdcdata.
  PERFORM f_bdc_field   USING 'BDC_OKCODE'     '/00'
                        CHANGING lt_bdcdata.
  PERFORM f_bdc_field   USING 'J_1BDYDOC-DOCNUM' gv_docnum
                        CHANGING lt_bdcdata.

  " Tela do documento - acionar 'Anular status do documento' (=ASTA)
  PERFORM f_bdc_dynpro  USING 'SAPLJ1BB2'  '2000'
                        CHANGING lt_bdcdata.
  PERFORM f_bdc_field   USING 'BDC_OKCODE'  '=ASTA'
                        CHANGING lt_bdcdata.

  " Confirmar popup de anulação (Enter)
  PERFORM f_bdc_dynpro  USING 'SAPLSPO1'  '0100'
                        CHANGING lt_bdcdata.
  PERFORM f_bdc_field   USING 'BDC_OKCODE'  'JA'
                        CHANGING lt_bdcdata.

  " Retornar à tela inicial
  PERFORM f_bdc_dynpro  USING 'SAPMJ1B1'  '1100'
                        CHANGING lt_bdcdata.
  PERFORM f_bdc_field   USING 'BDC_OKCODE'   '/EBACK'
                        CHANGING lt_bdcdata.
  PERFORM f_bdc_field   USING 'BDC_CURSOR'   'J_1BDYDOC-DOCNUM'
                        CHANGING lt_bdcdata.

  CALL TRANSACTION 'J1BNFE'
    USING    lt_bdcdata
    MODE     gv_mode
    UPDATE   'S'
    MESSAGES INTO lt_bdcmsg.

  PERFORM f_check_bdc_messages USING lt_bdcmsg 'ANULAR STATUS'.

ENDFORM.

*----------------------------------------------------------------------*
* BDC de ajuste - Transação J1B2N (recording fornecido)
*----------------------------------------------------------------------*
FORM f_bdc_ajuste.

  DATA: lt_bdcdata  TYPE TABLE OF bdcdata,
        ls_bdcdata  TYPE bdcdata,
        lt_bdcmsg   TYPE TABLE OF bdcmsgcoll,
        lv_item     TYPE i,
        lv_item_str TYPE char3.

  " Formatar data no padrão DD.MM.YYYY
  WRITE gs_nfdoc-docdat TO gv_date_f DD/MM/YYYY.
  REPLACE ALL OCCURRENCES OF '/' IN gv_date_f WITH '.'.

  " --- Tela inicial J1B2N ---
  PERFORM f_bdc_dynpro USING 'SAPMJ1B1' '1100'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR'       'J_1BDYDOC-DOCNUM'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'       '/00'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-DOCNUM' gv_docnum
                       CHANGING lt_bdcdata.

  " --- Tela 2000: cabeçalho do documento ---
  PERFORM f_bdc_dynpro USING 'SAPLJ1BB2' '2000'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'        '=LIDE'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-SERIES'  gs_nfdoc-series
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-DOCDAT'  gv_date_f
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-PSTDAT'  gv_date_f
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_SUBSCR'
                       'SAPLJ1BB2                               5400MAIN_PARTNER'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_SUBSCR'
                       'SAPLJ1BB2                               2100HEADER_TAB'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR'         'J_1BDYLIN-TMISS(01)'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_SUBSCR'
                       'SAPLJ1BB2                               2002NF_NUMBER'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-NFENUM'   gs_nfdoc-nfenum
                       CHANGING lt_bdcdata.

  " --- Tela 3000: itens (loop para cada linha) ---
  LOOP AT gt_nflin INTO gs_nflin.
    lv_item = sy-tabix.
    lv_item_str = lv_item.

    " Formatar quantidade tributável
    WRITE gs_nflin-menge_trib TO gv_menge_f.
    CONDENSE gv_menge_f.

    PERFORM f_bdc_dynpro USING 'SAPLJ1BB2' '3000'
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_OKCODE'          '=SAVE'
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYDOC-SERIES'    gs_nfdoc-series
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
                         'SAPLJ1BB2                               5400MAIN_PARTNER'
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
                         'SAPLJ1BB2                               3100ITEM_TABS'
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_CURSOR'          'J_1BDYLIN-CLASSTRIB'
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-ITMTYP'    gs_nflin-itmtyp
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-CHARG'     gs_nflin-charg
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-CFOP'      gs_nflin-cfop
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW1'    gs_nflin-taxlw1
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-MATORG'    gs_nflin-matorg
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW2'    gs_nflin-taxlw2
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW4'    gs_nflin-taxlw4
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-NBM'       gs_nflin-nbm
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-TAXLW5'    gs_nflin-taxlw5
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-CLASSTRIB' gs_nflin-classtrib
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
                         'SAPLJ1BB2                               3110SUB1'
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-COD_CTA'   gs_nflin-cod_cta
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-NUM_ITEM'  gs_nflin-num_item
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-MENGE_TRIB' gv_menge_f
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYLIN-MEINS_TRIB' gs_nflin-meins_trib
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'BDC_SUBSCR'
                         'SAPLJ1BB2                               2002NF_NUMBER'
                         CHANGING lt_bdcdata.
    PERFORM f_bdc_field  USING 'J_1BDYDOC-NFENUM'   gs_nfdoc-nfenum
                         CHANGING lt_bdcdata.
  ENDLOOP.

  " --- Retorno à tela inicial ---
  PERFORM f_bdc_dynpro USING 'SAPMJ1B1' '1100'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'  '/EBACK'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR'  'J_1BDYDOC-DOCNUM'
                       CHANGING lt_bdcdata.

  CALL TRANSACTION 'J1B2N'
    USING    lt_bdcdata
    MODE     gv_mode
    UPDATE   'S'
    MESSAGES INTO lt_bdcmsg.

  PERFORM f_check_bdc_messages USING lt_bdcmsg 'AJUSTE J1B2N'.

ENDFORM.

*----------------------------------------------------------------------*
* Reenviar para autorização na J1BNFE (=ENFE - Enviar NF-e)
*----------------------------------------------------------------------*
FORM f_reenviar_autorizacao.

  DATA: lt_bdcdata TYPE TABLE OF bdcdata,
        ls_bdcdata TYPE bdcdata,
        lt_bdcmsg  TYPE TABLE OF bdcmsgcoll.

  " Tela inicial - informar DOCNUM
  PERFORM f_bdc_dynpro USING 'SAPMJ1B1' '1100'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR'        'J_1BDYDOC-DOCNUM'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'        '/00'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'J_1BDYDOC-DOCNUM'  gv_docnum
                       CHANGING lt_bdcdata.

  " Tela do documento - acionar envio para autorização (=ENFE)
  PERFORM f_bdc_dynpro USING 'SAPLJ1BB2' '2000'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'  '=ENFE'
                       CHANGING lt_bdcdata.

  " Confirmar popup de envio (JA = Sim)
  PERFORM f_bdc_dynpro USING 'SAPLSPO1'  '0100'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'  'JA'
                       CHANGING lt_bdcdata.

  " Retornar à tela inicial
  PERFORM f_bdc_dynpro USING 'SAPMJ1B1' '1100'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_OKCODE'  '/EBACK'
                       CHANGING lt_bdcdata.
  PERFORM f_bdc_field  USING 'BDC_CURSOR'  'J_1BDYDOC-DOCNUM'
                       CHANGING lt_bdcdata.

  CALL TRANSACTION 'J1BNFE'
    USING    lt_bdcdata
    MODE     gv_mode
    UPDATE   'S'
    MESSAGES INTO lt_bdcmsg.

  PERFORM f_check_bdc_messages USING lt_bdcmsg 'REENVIO AUTORIZAÇÃO'.

ENDFORM.

*----------------------------------------------------------------------*
* Helpers BDC
*----------------------------------------------------------------------*
FORM f_bdc_dynpro USING pv_prog TYPE any
                        pv_dyn  TYPE any
                  CHANGING ct_bdc TYPE TABLE.

  DATA ls_bdc TYPE bdcdata.
  ls_bdc-program  = pv_prog.
  ls_bdc-dynpro   = pv_dyn.
  ls_bdc-dynbegin = 'X'.
  APPEND ls_bdc TO ct_bdc.

ENDFORM.

FORM f_bdc_field USING pv_fname TYPE any
                       pv_fval  TYPE any
                 CHANGING ct_bdc TYPE TABLE.

  DATA ls_bdc TYPE bdcdata.
  ls_bdc-fnam = pv_fname.
  ls_bdc-fval = pv_fval.
  APPEND ls_bdc TO ct_bdc.

ENDFORM.

*----------------------------------------------------------------------*
* Verificar e exibir mensagens BDC
*----------------------------------------------------------------------*
FORM f_check_bdc_messages USING pt_msg   TYPE TABLE
                                pv_etapa TYPE string.

  DATA: ls_msg   TYPE bdcmsgcoll,
        lv_txt   TYPE string,
        lv_erro  TYPE abap_bool VALUE abap_false.

  LOOP AT pt_msg INTO ls_msg.
    CALL FUNCTION 'MESSAGE_TEXT_BUILD'
      EXPORTING
        msgid               = ls_msg-msgid
        msgnr               = ls_msg-msgnr
        msgv1               = ls_msg-msgv1
        msgv2               = ls_msg-msgv2
        msgv3               = ls_msg-msgv3
        msgv4               = ls_msg-msgv4
      IMPORTING
        message_text_output = lv_txt.

    WRITE: / |[{ pv_etapa }] { ls_msg-msgtyp }: { lv_txt }|.

    IF ls_msg-msgtyp = 'E' OR ls_msg-msgtyp = 'A'.
      lv_erro = abap_true.
    ENDIF.
  ENDLOOP.

  IF lv_erro = abap_true.
    WRITE: / |*** Etapa "{ pv_etapa }" finalizada com ERRO. Verifique as mensagens acima. ***|.
  ELSE.
    WRITE: / |>>> Etapa "{ pv_etapa }" executada com sucesso. <<<|.
  ENDIF.

ENDFORM.
